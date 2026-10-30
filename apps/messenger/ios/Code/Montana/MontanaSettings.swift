//
//  MontanaSettings.swift
//  Montana — a Montana messenger
//
//  Cut out of ContentView.swift whole, declaration by declaration (the author's word 10.09):
//  nothing here was renamed or rewritten; the file holds one screen and what only it reads.
//

import SwiftUI
import CryptoKit
import MontanaBindings
import PhotosUI
import Photos
import Contacts
import UserNotifications
import UIKit
import UniformTypeIdentifiers
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



// ── "Settings" tab / profile ──
enum SettingsSheet: Int, Identifiable { case emoji, qr; var id: Int { rawValue } }

// Reliable overscroll reading: finds the enclosing UIScrollView (List) and observes contentOffset (KVO).
// pull = how far the list is dragged down past the top (for expanding the avatar,).
struct ScrollProbe: UIViewRepresentable {
    var onPull: (CGFloat) -> Void
    var onAttach: (UIScrollView) -> Void = { _ in }
    /// The finger is released. The reference decides exactly here where to snap the header
    /// (scrollViewWillEndDragging → targetContentOffset), so it never rests in-between.
    var onDragEnd: (UIScrollView) -> Void = { _ in }
    func makeUIView(context: Context) -> UIView {
        let v = UIView(); v.isUserInteractionEnabled = false
        DispatchQueue.main.async {
            context.coordinator.attach(from: v, onPull: onPull, onAttach: onAttach, onDragEnd: onDragEnd)
        }
        return v
    }
    func updateUIView(_ v: UIView, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator {
        // A list recycles its rows: the view that carried the probe can go while the list stays, and a
        // target left on the list's own pan would be messaged after this coordinator is gone.
        deinit { scrollRef?.panGestureRecognizer.removeTarget(self, action: #selector(panChanged(_:))) }
        private var obs: NSKeyValueObservation?
        private var dragEnd: ((UIScrollView) -> Void)?
        private weak var scrollRef: UIScrollView?

        @objc func panChanged(_ g: UIPanGestureRecognizer) {
            guard g.state == .ended || g.state == .cancelled, let sv = scrollRef else { return }
            dragEnd?(sv)
        }

        func attach(from view: UIView, onPull: @escaping (CGFloat) -> Void,
                    onAttach: @escaping (UIScrollView) -> Void = { _ in },
                    onDragEnd: @escaping (UIScrollView) -> Void = { _ in }, tries: Int = 12) {
            var sv: UIView? = view.superview
            while let s = sv, !(s is UIScrollView) { sv = s.superview }
            guard let scroll = sv as? UIScrollView else {
                if tries > 0 {   // the lazy List may not have mounted the scrollview yet — retry
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                        self?.attach(from: view, onPull: onPull, onAttach: onAttach,
                                     onDragEnd: onDragEnd, tries: tries - 1)
                    }
                }
                return
            }
            onAttach(scroll)
            scrollRef = scroll
            dragEnd = onDragEnd
            scroll.panGestureRecognizer.addTarget(self, action: #selector(panChanged(_:)))
            obs = scroll.observe(\.contentOffset, options: [.initial, .new]) { s, _ in
                let raw = -(s.contentOffset.y + s.adjustedContentInset.top)   // >0 dragged down, <0 scrolled
                onPull(raw)
            }
        }
    }
}

struct SettingsTabView: View {
    /// THE WAY OUT (the author's word 17.09): the system's cross top left, the done mark's format —
    /// handed in by the page that presents the sheet; absent, the page stands as a tab and has none.
    var onClose: (() -> Void)? = nil
    @AppStorage("userName") private var displayName: String = ""
    @AppStorage("avatarData") private var avatarData: Data = Data()
    @AppStorage("avatarGallery") private var avatarGalleryJSON: String = ""
    @AppStorage("statusEmoji") private var statusEmoji: String = ""
    private let testMode = false
    @State private var pickerItem: PhotosPickerItem?
    @State private var cropSource: MTCropSource?   // the picked photo awaiting its circle
    @State private var refCopied = false
    @State private var showProfile = false
    @State private var activeSheet: SettingsSheet?
    @State private var showScan = false

    private var fullName: String { displayName.trimmingCharacters(in: .whitespaces) }
    /// This person's face — one question, one answer ([C-1]): the same resolver as for peers.
    // USER-DATA: the person's own glyph or letter, not interface text.
    private var myFace: String { E2E.myFaceGlyph() }

    var body: some View {
        NavigationStack {
            // THE SETTINGS ARE THE PLATFORM'S OWN LIST (the author's word 25.09: «bring the first page over to the same native List
            // with sections on MTGlassRowPlate, as the notifications»): no face and no name at the head -- my page shows them --
            // every section a List section, its rows the list's own rows on the one-tone glass, with the list's own separators,
            // insets and chevrons, exactly as the notifications page stands.
            List {
                // THE 24 WORDS AT THE HEAD (the author's word 08.10.2026: «bring the seed up to the top of Settings, as in Business»):
                // the one thing nobody can give back stands first; Privacy keeps its own row beside the account's deletion.
                Section {
                    NavigationLink { SeedShowView().montanaMotionMeter() } label: { navLabel("Save 24 words", "key.horizontal.fill", .gray) }
                } footer: {
                    Text("Write the 24 words down and keep them: on a new phone your identity and your saved history open only from them.")
                }
                .listRowBackground(MTGlassRowPlate())
                Section {
                    NavigationLink { NotificationsView() } label: { navLabel("Notifications and Sounds", "bell.badge.fill", .red) }
                    NavigationLink { MTFolderSettingsPage() } label: { navLabel("Chat Folders", "folder.fill", .blue) }   // the folders' tabs (17.10.2026)
                    NavigationLink { DataStorageView() } label: { navLabel("Data and Storage", "arrow.down.circle.fill", .indigo) }
                    NavigationLink { HomeNodeView() } label: { navLabel("Your node", "server.rack", .gray) }
                    NavigationLink { PrivacyView() } label: { navLabel("Privacy", "lock.fill", .gray) }
                    NavigationLink { MTLevelAccessPage() } label: { navLabel("Access by level", "stairs", .orange) }
                    NavigationLink { AppearanceView() } label: { navLabel("Appearance", "paintbrush.fill", .blue) }
                    NavigationLink { LanguagePickerView() } label: { navLabel("Language", "globe", .cyan) }
                }
                .listRowBackground(MTGlassRowPlate())
                Section {
                    NavigationLink { MTQuestionsPage() } label: { navLabel("Questions", "questionmark.bubble.fill", .green) }   // the answers of this build (17.10.2026)
                    NavigationLink { SupportView() } label: { navLabel("Ask a question", "questionmark.circle.fill", .blue) }
                    NavigationLink { MontanaTermsView() } label: { navLabel("Terms of Use", "doc.text.fill", .gray) }
                    // THE POLICY STANDS WHERE THE TERMS STAND (App Review 5.1.1(i), 08.10.2026): reachable from inside the app, not only
                    // under the first door; it opens on the site in the languages the site speaks (MontanaSafety.privacy).
                    Button { if let u = URL(string: MontanaSafety.privacy) { UIApplication.shared.open(u) } } label: { navLabel("Privacy Policy", "hand.raised.fill", .blue) }
                }
                .listRowBackground(MTGlassRowPlate())
            }
            .scrollContentBackground(.hidden)
            .contentMargins(.bottom, 96, for: .scrollContent)
            .montanaPageGround()   // my page's ground, as the drawer and my page wear it (25.09)
            // ONE BAR ON EVERY PAGE OF THE STACK (25.09, T1: «it lags and flickers on the way back by the arrow»): the root hid the
            // navigation bar and every page inside showed it, so each push and pop toggled the bar and laid the root out twice
            // in the middle of the move -- its rows jumped by the bar's height as the bar left. The root wears the bar too,
            // inline, and THE CROSS top left (the author's word 17.09) is the one mark of the bar (MontanaCloseMark), as on
            // every sheet. The profile is edited from my page, by its mark top right (the author's word 25.09): none here.
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if let onClose {
                    ToolbarItem(placement: .topBarLeading) { MontanaCloseMark(action: onClose) }
                }
            }
            .onChange(of: pickerItem) { _, item in
                Task {
                    if let data = try? await item?.loadTransferable(type: Data.self),
                       let img = UIImage(data: data) {
                        cropSource = MTCropSource(image: img)   // the circle decides what the face keeps
                    }
                }
            }
            .fullScreenCover(item: $cropSource) { src in
                MTAvatarCropView(image: src.image) { jpeg in
                    cropSource = nil
                    guard let jpeg else { return }
                    if let name = saveToDocs(jpeg, ext: "jpg") {
                        var list = (try? JSONDecoder().decode([String].self, from: Data(avatarGalleryJSON.utf8))) ?? []
                        list.insert(name, at: 0)
                        avatarGalleryJSON = String(data: (try? JSONEncoder().encode(list)) ?? Data(), encoding: .utf8) ?? ""
                    }
                    MontanaSelfFace.set(jpeg)
                }
            }
            .sheet(item: $activeSheet) { s in
                Group {
                    switch s {
                    case .emoji: emojiSheet
                    case .qr: qrSheet
                    }
                }
                .montanaMotionMeter()   // every rise and fall of a sheet is measured (25.09)
            }
            .sheet(isPresented: $showScan) {
                NavigationStack {
                    ScanMeetingView { conv in
                        showScan = false
                        // full chat via the same path as the «Chats» tab/notification (no modal)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            NotificationCenter.default.post(name: .openChatRequest, object: nil, userInfo: ["address": conv])
                        }
                    }
                    .toolbar { ToolbarItem(placement: .cancellationAction) { MontanaCloseMark { showScan = false } } }
                }.preferredColorScheme(.dark).montanaMotionMeter()
            }
        }
    }

    func goldRow(_ title: String, _ icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 16, weight: .semibold))
                .foregroundColor(Color.accentColor).frame(width: 26)
            Text(LocalizedStringKey(title)).foregroundColor(.accentColor)
            Spacer()
        }
    }
    var qrSheet: some View {
        NavigationStack {
            VStack {
                Spacer(minLength: 8)
                MontanaCodeView(name: MontanaSelf.name, onScan: {
                    activeSheet = nil   // the sheet closes, otherwise the camera waits for its collapse
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { showScan = true }
                }, onMet: { activeSheet = nil })
                Spacer(minLength: 8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity).montanaPageGround()   // my page's ground, as every page wears it (26.09)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    MontanaDoneMark { activeSheet = nil }
                }
            }
        }.preferredColorScheme(.dark)
    }
    var emojiSheet: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 16) {
                    Button { statusEmoji = ""; activeSheet = nil } label: {
                        Text("no").font(.caption).foregroundColor(.gray).frame(width: 40, height: 40)
                    }
                    ForEach(montanaStickers, id: \.self) { e in
                        Button { statusEmoji = e; activeSheet = nil } label: {
                            Text(e).font(.system(size: 32)).frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }.padding()
            }.frame(maxWidth: .infinity, maxHeight: .infinity).montanaPageGround()   // my page's ground, as every page wears it (26.09)
        }.preferredColorScheme(.dark).presentationDetents([.medium])
    }
    // colored icon + title (for links to sub-screens)
    // One settings row is drawn in one place: `settingsToggleLabel`. A second copy would
    // diverge in padding on the first edit, and two rows of one list would sit differently.
    func navLabel(_ title: String, _ icon: String, _ color: Color) -> some View {
        settingsToggleLabel(LocalizedStringKey(title), icon, color)
    }
}

// ════════════════════════════════════════════════════════════
// SETTINGS SUB-SCREENS
// ════════════════════════════════════════════════════════════

// Questions
/// QUESTIONS (the author's words 17.10.2026 19:50 UTC: «make all of these into a section of questions: answers to every question in
/// the app as a separate section, with all the information and the documents, public, so that AI agents read the link to montana.xxx
/// and learn every rule of the app for the person»; 20:18 UTC: «everything into build 2238»): the platform's own list, a section a
/// topic, a row a question, the whole row the road to its answer. Every answer says only what this build keeps -- the levels and the
/// minting as MTPersonChain, MTPiLevels and MTLevelAccess hold them (APPLE-RULES 2.1, 2.3.1(a)); the same answers, with the
/// specification's, stand on montana.xxx/faq for people and for the agents that read the site (MontanaSafety.guide).
struct MTQuestionsPage: View {
    struct Item: Identifiable { let question: String; let answer: String; var id: String { question } }
    struct Topic: Identifiable { let title: String; let systemImage: String; let items: [Item]; var id: String { title } }
    static let topics: [Topic] = [
        Topic(title: "Levels", systemImage: "stairs", items: [
            Item(question: "What is the Global level?",
                 answer: "Your Global level is the lowest of three levels: the level of the chain of the person, which grows with your time on the network, the level of π, which grows with the coins you hold, and the Fabric of Time, which stands on the people you write to and call regularly in the last two weeks. You see it in TimeCoin, on the TimeChain page, and in Settings, under Access by level."),
            Item(question: "How does the chain of the person count my time?",
                 answer: "A second counts while Montana is open on the screen of one of your devices and a Montana node answers it. The second is read from the node, never from the clock of your phone. Each level doubles the seconds of the one before: 1 second is level 0, 2 seconds level 1, 4 seconds level 2, then 8, 16, 32 and on. When you leave the network, your level stays, and nothing is added until you return."),
            Item(question: "What is the level of π?",
                 answer: "It is the level of your wallet: how many first digits of π your balance reaches. 3 coins is level 1, 31 coins level 2, 314 coins level 3, then 3141, 31415 and on, up to 19 digits. Below 3 coins the level is 0. It is the one level you lower yourself: it falls when your balance falls."),
            Item(question: "What do the levels open?",
                 answer: "Each level opens functions of Montana. Level 7 opens Forbid deletion on my phone: a message your correspondent deletes for everyone stays on your phone, and their phone is told so. Level 7 also opens Record calls: calls are recorded by themselves on your phone and sent to the call's chat after your first consent. Level 8 opens your own node: a machine you own joins the Montana network through this app. All of them are in Settings, under Access by level."),
            Item(question: "Can I record a call below level 7?",
                 answer: "Yes. On every level a call can be recorded by the record button on the call screen, unless your correspondent's switch holds. From level 7 calls are recorded by themselves once you agree the first time, and you can turn it off in Settings, under Access by level."),
            Item(question: "Who can record a call with me?",
                 answer: "While your Record calls switch in Access by level is off, and below level 7 it stands off, a correspondent whose Global level is not above yours cannot record your calls: neither by themselves nor by the record button, which they do not see. A correspondent with a higher level records on their side only; your phone records nothing, and the chat is told that the call is being recorded. A version of Montana that does not say the switch forbids nothing."),
            Item(question: "Who sends the recording to the chat?",
                 answer: "In a one-to-one call the caller sends the recording to the chat. When the caller does not record, the one who answered sends it, so a recorded call always reaches the chat, once."),
            Item(question: "Can I take my copy back from my node below level 8?",
                 answer: "Yes. Setting up your node and sending copies to it open at level 8. Taking your copy back from it is open on every level."),
        ]),
        // THE FABRIC OF TIME (the author's words 17.10.2026 19:24-19:50 UTC; 17.10.2026 21:4x «a sliding window of t2 over live activity»,
        // 07:2x a correspondent weighed by their ceiling; MTFabric): what this build does of it and no more -- its deviations from the
        // specification named, not hidden (the window from the nodes' seconds, no witness into the network yet).
        Topic(title: "Fabric of Time", systemImage: "point.3.connected.trianglepath.dotted", items: [
            Item(question: "What is the Fabric of Time?",
                 answer: "The third level your Global level is set by: the people you write to and call regularly, each weighed by the level their own time and wallet give them. Your Global level is the lowest of the three, so the Fabric of Time can lower it and never raises it."),
            Item(question: "What counts as an exchange?",
                 answer: "Anything you and a person send each other that stands in your conversation: words, voice and video messages, photos, files, stickers and GIFs, coin transfers, the moves of a game, and a call in which each phone received the other's voice for at least 60 seconds. Receipts, typing and presence do not count, and neither does a group."),
            Item(question: "When does a person's phone sign for me?",
                 answer: "When a word of yours reaches their phone and they wrote to you themselves in the last 7 days, their phone signs, once a day at most, that your word reached it: the minute it arrived, the hash the fingerprint of your conversation is read from, and their own ceiling. It gives the signature to you alone, inside your conversation. A person who only writes and is never answered receives none."),
            Item(question: "Who is a regular correspondent?",
                 answer: "A person from whom your phone holds a signature in each of the last two weeks: the newer 7 days and the 7 before them. The window slides with the clock of the network; there are no fixed weeks. People are told apart by the key their signatures are made with, which their 24 words give for your conversation alone, not by anything they say about themselves."),
            Item(question: "How is the level of the Fabric of Time counted?",
                 answer: "Each regular correspondent stands at their ceiling: the lower of their two other levels, at its lowest in their signatures of the last two weeks. The level is the greatest number g for which at least g of your regular correspondents stand at g or above; a person far above g adds one, exactly as one at g does. It is counted again whenever a signature arrives or leaves the two weeks. Their own Fabric of Time does not enter it, so one person's dip never pulls a whole circle down."),
            Item(question: "Does the Fabric of Time lower a newcomer?",
                 answer: "Not in the first two weeks. From the first launch of this version on this phone with your 24 words, for 14 days the Fabric of Time stands at your ceiling, so your Global level follows your two other levels. TimeCoin and Access by level show the days left until the first count."),
            Item(question: "What do the people I write to learn?",
                 answer: "Your ceiling, inside the signatures your phone gives them, and nothing else of the Fabric of Time. A signature names your conversation by the hash its fingerprint is read from, which only the two of you can compute, and it is made with a key your 24 words give for that conversation alone. No key and no number in it is the same with two people, so two people you write to cannot tell from it that they speak with the same person."),
            Item(question: "What do the nodes of the network learn?",
                 answer: "Nothing they can read: signatures and ceilings ride inside your conversation, sealed for the other person, by the same road as your letters. Signatures stay on your phone for two weeks and then leave it."),
            Item(question: "How does this version differ from the specification?",
                 answer: "In four ways. A phone holds no window of the network's core, so the minute of a signature and the two weeks are read from the clock of the Montana nodes, learned from their answers. The signatures are not yet witnessed into the network; they stay on the phone that received them. Each of your devices with the same 24 words counts the signatures that reached it. And a signature names a conversation and is made with a key for that conversation alone, where the specification names the key of a person: this version knows people only by their conversations."),
            Item(question: "Can false signatures lift a level?",
                 answer: "No. The Fabric of Time only lowers: a person who states a false ceiling can at most spare someone a lowering and never lifts anyone above their own ceiling. One signature a day from one person is kept, the one with the lower ceiling, so two of their devices answering the same word weigh as one."),
        ]),
        Topic(title: "Coins and time", systemImage: "hourglass", items: [
            Item(question: "What is a Time Coin?",
                 answer: "The coin of Montana, ticker $TCM. Its measure is time: one second is one coin, so an hour is 3600 coins. A billion coins is one Montana."),
            Item(question: "Do coins mint while Montana is in the background?",
                 answer: "Yes. When Montana leaves the screen, it keeps the moment it left. When you come back, every second you were away mints one coin, the same one coin a second as everywhere. At Global level 0 the time away mints nothing, and neither does it when the network did not answer Montana before it left the screen. Both moments are read from the Montana network, so turning the clock of the phone changes nothing."),
        ]),
        Topic(title: "Your words and devices", systemImage: "key.horizontal", items: [
            Item(question: "What if I use Montana on several devices?",
                 answer: "The same 24 words on several devices are one person. Their seconds join: two devices open in the same second add one second, and once the devices have read each other's count, they show one chain of the person."),
            Item(question: "What if I have several sets of 24 words?",
                 answer: "Each set of 24 words is a separate person: its own seconds, its own wallet, its own levels. The levels of two persons are never added together, and coins move between them only by a real transfer."),
        ]),
        Topic(title: "Privacy", systemImage: "lock", items: [
            Item(question: "Who sees my level?",
                 answer: "The people you write with see your Global level beside your avatar. The nodes of the network keep a table of how many people stand on each level: for it Montana gives them a mark made from your 24 words and your Global level, never your balance, name or contacts. Your seconds online leave the phone only sealed under your 24 words: the nodes keep them for your other devices and cannot read them."),
        ]),
    ]
    var body: some View {
        List {
            ForEach(Self.topics) { topic in
                Section {
                    ForEach(topic.items) { item in
                        NavigationLink { MTAnswerPage(topic: topic.title, item: item) } label: {
                            Text(LocalizedStringKey(item.question)).frame(minHeight: 44, alignment: .leading)
                        }
                    }
                } header: {
                    Label(LocalizedStringKey(topic.title), systemImage: topic.systemImage)
                }
                .listRowBackground(MTGlassRowPlate())
            }
            Section {
                MTDocumentRow(title: "Questions and answers", link: MontanaSafety.guide)
                MTDocumentRow(title: "Specification and code", link: MontanaSafety.source)
            } header: {
                Label("Documents", systemImage: "doc.text")
            } footer: {
                Text("The site holds the answers about Montana in English, Russian and Chinese, also as files AI assistants read. The Montana specification and the code of this app are open on GitHub.")
            }
            .listRowBackground(MTGlassRowPlate())
        }
        .foregroundColor(.primary)
        .scrollContentBackground(.hidden)
        .montanaPageGround()
        .navigationTitle("Questions")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// One answer on a page of its own: the question over its answer in the list's own row, as the platform's help reads.
struct MTAnswerPage: View {
    let topic: String
    let item: MTQuestionsPage.Item
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text(LocalizedStringKey(item.question)).font(.headline)
                    Text(LocalizedStringKey(item.answer)).font(.body).fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 6)
            }
            .listRowBackground(MTGlassRowPlate())
        }
        .foregroundColor(.primary)
        .scrollContentBackground(.hidden)
        .montanaPageGround()
        .navigationTitle(Text(LocalizedStringKey(topic)))
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// A document of Montana, opened in the platform's own browser sheet inside the app (MTExplorerSheet); the whole row is the target.
struct MTDocumentRow: View {
    let title: String
    let link: String
    var body: some View {
        Button { if let u = URL(string: link) { MTExplorerSheet.open(u) } } label: {
            HStack {
                Label(LocalizedStringKey(title), systemImage: "safari")
                Spacer()
                // USER-DATA: an address
                Text(verbatim: link.replacingOccurrences(of: "https://", with: "")).font(.footnote).foregroundColor(.gray).lineLimit(1)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .foregroundColor(.primary)
    }
}

// Notifications and sounds
struct NotificationsView: View {
    @AppStorage("notifSound") private var sound = true
    @AppStorage("notifPreview") private var preview = true
    @AppStorage("notifSender") private var showSender = true
    @AppStorage("notifLockName") private var nameOnLock = true   // read by MontanaNotifyGate.nameOnLockScreen
    @State private var status: UNAuthorizationStatus = .notDetermined

    /// The catalog key as a string: both the person and the check see the word is translated.
    private var statusKey: String {
        switch status {
        case .authorized, .provisional, .ephemeral: return "Connected"
        case .denied: return "Disconnected"
        default: return "Not asked"
        }
    }

    private func icon(_ name: String, _ color: Color) -> some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(color)
            .frame(width: 29, height: 29)
            .overlay(Image(systemName: name).font(.system(size: 15, weight: .medium)).foregroundColor(.white))
    }

    var body: some View {
        List {
            Section {
                Button {
                    if status == .notDetermined { MontanaNotifyGate.ask() } else { MontanaSystemSettings.open() }
                } label: {
                    HStack(spacing: 12) {
                        icon("bell.badge.fill", .red)
                        Text("Allow notifications").foregroundColor(.primary)
                        Spacer()
                        Text(LocalizedStringKey(statusKey)).foregroundColor(.gray)
                        Image(systemName: "chevron.right").foregroundColor(Color(white: 0.35)).font(.footnote.weight(.semibold))
                    }
                    .contentShape(Rectangle())   // the whole row is the target, not only its words (22.09)
                }
            }
            .listRowBackground(MTGlassRowPlate())

            Section {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 12) {
                        icon("speaker.wave.2.fill", .pink)
                        Toggle("Sound", isOn: $sound)
                    }
                    Text("Notifications of new messages play a sound. Off, they arrive silently.")
                        .font(.caption).foregroundColor(.gray)
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 12) {
                        icon("text.bubble.fill", .green)
                        Toggle("Show message text", isOn: $preview)
                    }
                    Text("A notification shows the words of the message. Off, it shows none of them.")
                        .font(.caption).foregroundColor(.gray)
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 12) {
                        icon("person.fill", .orange)
                        Toggle("Show sender", isOn: $showSender)
                    }
                    Text("A notification of a message shows who wrote and their photo. Off, it reads Montana instead.")
                        .font(.caption).foregroundColor(.gray)
                }
                // The name stands on the locked screen even when the system hides previews:
                // a native category option, re-registered the moment the switch flips.
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 12) {
                        icon("lock.fill", .blue)
                        Toggle("Show name on lock screen", isOn: $nameOnLock)
                    }
                    Text("When the phone hides previews on the lock screen, the notification still names who wrote.")
                        .font(.caption).foregroundColor(.gray)
                }
            }
            .listRowBackground(MTGlassRowPlate())
        }
        .onChange(of: nameOnLock) { _, _ in MontanaNotifyGate.registerCategories() }
        .foregroundColor(.primary)   // the switches wear the system's own green (the author's word 25.09)
        .scrollContentBackground(.hidden)
        .montanaPageGround()   // my page's ground, as the drawer and my page wear it (25.09)
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { MontanaNotifyGate.systemStatus { status = $0 } }
        // Returning to the app is that very event: the person may have changed the permission in Settings.
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            MontanaNotifyGate.systemStatus { status = $0 }
        }
        // Mirror ALL notification settings into the shared keychain — for the extension (NSE) in the background.
        .onChange(of: sound) { _, on in MontanaKeychain.set("notifSound", Data([on ? 1 : 0])) }
        .onChange(of: preview) { _, on in MontanaKeychain.set("notifPreview", Data([on ? 1 : 0])) }
        .onChange(of: showSender) { _, on in MontanaKeychain.set("notifSender", Data([on ? 1 : 0])) }
        .onAppear { MontanaNotifyGate.mirrorSettings() }
    }
}

// Privacy
// Live app-language switching: we swap the localization bundle,
// SwiftUI re-reads Text when AppLanguage changes. Default — system (no hardcoding).
final class LocalizedBundle: Bundle, @unchecked Sendable {
    override func localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        // The one language (MTLanguage): the choice, the system's first when ours, else English.
        let b = MTLanguage.bundle
        if b !== self { return b.localizedString(forKey: key, value: value, table: tableName) }
        return super.localizedString(forKey: key, value: value, table: tableName)
    }
    static let install: Void = {
        object_setClass(Bundle.main, LocalizedBundle.self)
    }()
}

struct MontanaLanguage: Identifiable, Equatable {
    let id: String        // "" = system, otherwise the lproj code
    let native: String    // as on the screenshot: large, in its own language
    let english: String   // caption below
    let flag: String
}

struct LanguagePickerView: View {
    @AppStorage("AppLanguage") private var lang: String = ""
    @Environment(\.dismiss) private var dismiss
    private let options: [MontanaLanguage] = [
        MontanaLanguage(id: "", native: "System", english: "System · Auto", flag: "globe"),
        MontanaLanguage(id: "en", native: "English", english: "English", flag: "🇬🇧"),
        MontanaLanguage(id: "zh-Hans", native: "简体中文", english: "Chinese", flag: "🇨🇳"),
        MontanaLanguage(id: "ru", native: "Русский", english: "Russian", flag: "🇷🇺"),   // CYRILLIC-DATA-OK: the language's own native name, user-facing data
    ]
    var body: some View {
        // THE PLATFORM'S OWN LIST, AS THE NOTIFICATIONS (the author's word 25.09: «the same on the language page»): one section on
        // the one-tone glass with the list's own separators; the chosen language wears the system's green check.
        List {
            Section {
                ForEach(options) { o in
                    Button {
                        lang = o.id
                        // apply immediately for system APIs; SwiftUI Text will re-read via the bundle
                        if o.id.isEmpty { UserDefaults.standard.removeObject(forKey: "AppleLanguages") }
                        else { UserDefaults.standard.set([o.id], forKey: "AppleLanguages") }
                        MTLanguage.mirror()   // the banners and the share sheet speak it too
                        NotificationCenter.default.post(name: .appLanguageChanged, object: nil)
                    } label: {
                        HStack(spacing: 14) {
                            ZStack {
                                Circle().fill(Color(white: 0.16)).frame(width: 44, height: 44)
                                if o.flag == "globe" { Image(systemName: "globe").foregroundColor(Color.accentColor) }
                                else { Text(o.flag).font(.title2) }
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(LocalizedStringKey(o.native)).font(.body).foregroundColor(.primary)
                                Text(LocalizedStringKey(o.english)).font(.caption).foregroundColor(.gray)
                            }
                            Spacer()
                            if lang == o.id { Image(systemName: "checkmark").foregroundColor(.green).font(.headline) }
                        }
                        .contentShape(Rectangle())   // the whole row is the target, not only its words (22.09)
                    }.buttonStyle(.plain)
                }
            } footer: {
                Text("Language change will take effect immediately.").foregroundColor(.gray)
            }
            .listRowBackground(MTGlassRowPlate())
        }
        .scrollContentBackground(.hidden)
        .montanaPageGround()   // my page's ground, as the drawer and my page wear it (25.09)
        .navigationTitle("Language").navigationBarTitleDisplayMode(.inline)
    }
}


// Data and Storage. For now — media autodownload only: whether attachments download by
// themselves. Off — the attachment keeps its download arrow and downloads on tap.

/// THE WALLPAPER OF ONE CHAT (the author's word 22.09): chosen from the profile's «More» — SEEN AND
/// NOT READ. The page holds no words: the circle of the chat's own ground and the circle of the photo
/// library stand at the top, the drawn grounds below as the platform's own suggestions do; every tile
/// answers the finger on ALL of itself, the chosen one wears the platform's check badge. A tap opens
/// the preview — the very ground with the very bubbles, full-screen — and only the checkmark sets it.
/// ONE CHOOSER FOR BOTH GROUNDS ([C-1], the author's word 23.09: "make the pages' background work
/// exactly as the chat's preview does"). The pages used to be chosen by a row of tiles living inside the
/// Appearance list — its own thumbnails, its own recent list, its own slider — while a chat was
/// chosen on this page and shown in the one preview. Two roads to one thing: the pages' tiles knew
/// nothing of the crop, and the slider stood a page away from the picture it softened. Now both walk
/// this page and the one preview; only the task differs.
struct MTWallpaperPicker: View {
    let task: MTWallpaperTask
    /// What the checkmark goes on to: the first screen makes the person after their ground is chosen (the author's word 30.09).
    var onDone: () -> Void = {}
    private var conv: String { task.key }
    @Environment(\.montanaClose) private var montanaClose
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var book = MTWallpaper.Book.shared
    @State private var photoItem: PhotosPickerItem?
    @State private var preview: MTWallpaperCandidate?
    @State private var tab = 0   // 0: the ready-made grounds; 1: the photo library, shown on the page itself
    private let cols = [GridItem(.adaptive(minimum: 104, maximum: 150), spacing: 14)]
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // TWO TABS, CLEARLY APART (the author's word 25.09: «the first tab is the choice among the ready-made wallpapers,
                // and a second one, switched to on its own, chooses from the photo gallery, shown on the page itself»): the
                // platform's own segmented control over the page; the library is the platform's own picker, inline.
                Picker(selection: $tab) {
                    Text("Wallpapers").tag(0)
                    Text("Photos").tag(1)
                } label: { EmptyView() }
                .pickerStyle(.segmented)
                .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 10)
                if tab == 0 {
                    ready
                } else {
                    // THE PHOTO LIBRARY ON THE PAGE ITSELF: the platform's own picker in its inline dress, its own bars hidden --
                    // a tap on a photo hands it to the preview, to be placed by the finger and kept as placed.
                    PhotosPicker(selection: $photoItem, matching: .images) { EmptyView() }
                        .photosPickerStyle(.inline)
                        .photosPickerAccessoryVisibility(.hidden, edges: .all)
                        .ignoresSafeArea(edges: .bottom)
                }
            }
            .montanaPageGround()   // my page's ground, as every page wears it (26.09)
            .navigationTitle(task.isPage ? LocalizedStringKey("Page background") : LocalizedStringKey("Chat background"))
            .navigationBarTitleDisplayMode(.inline)
            // THE CHECKMARK AT THE TOP RIGHT, AS THE PREVIEW WEARS IT (the author's word 25.09: «on the page that chooses the
            // profile's ground, put the native checkmark at the top right, the same as in the preview»): the cross at the left,
            // the checkmark at the right -- our bar's two marks; the ground itself is kept by the preview's checkmark, and this
            // one finishes the choosing and leaves with what stands chosen.
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { MontanaCloseMark { mtLeavePage(montanaClose, dismiss) } }
                ToolbarItem(placement: .topBarTrailing) {
                    MontanaDoneMark {
                        MontanaTrace.mark("wallpaper", "chooser done page=\(task.isPage ? 1 : 0)")
                        onDone()
                        mtLeavePage(montanaClose, dismiss)
                    }
                }
            }
            .onChange(of: photoItem) { _, item in
                Task {
                    guard let d = try? await item?.loadTransferable(type: Data.self), let ui = UIImage(data: d) else { return }
                    preview = MTWallpaperCandidate(choice: .general, picture: ui)   // placed by hand in the preview, saved as placed
                    photoItem = nil
                }
            }
        }
        // THE PREVIEW COVERS THE PAGE BENEATH, BAR AND ALL (the author's word 23.09: "take away the extra
        // cross at the top left"). The sliding page used to be mounted INSIDE the navigation stack, so the
        // chooser's own bar — with its cross — stayed drawn above it, and the preview showed a second
        // cross of its own right under the first. Mounted outside, one page shows one cross.
        .montanaPage(item: $preview) { c in
            MTWallpaperPreview(task: task, candidate: c)   // one preview for both tasks ([C-1])
        }
        .preferredColorScheme(.dark)
    }
    /// The two Montana grounds lead the chooser; the remaining catalogue stays available below as system grounds.
    private var ready: some View {
        ScrollView {
            let _ = book.rev
            let now = MTWallpaper.choice(for: conv)
            VStack(alignment: .leading, spacing: 18) {
                Text("Montana backgrounds")
                    .font(.headline.weight(.semibold))
                LazyVGrid(columns: cols, spacing: 14) {
                    ForEach(montanaGrounds, id: \.self) { c in namedTile(c, chosen: c == now) }
                }
                Text("System backgrounds")
                    .font(.headline.weight(.semibold))
                    .padding(.top, 4)
                LazyVGrid(columns: cols, spacing: 14) {
                    ForEach(systemGrounds, id: \.self) { c in tile(c, chosen: c == now) }
                }
                if let extra = extraGround(now) {
                    LazyVGrid(columns: cols, spacing: 14) { tile(extra, chosen: true) }
                }
            }
            .padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 24)
        }
    }
    private var montanaGrounds: [MTWallpaper.Choice] {
        MTWallpaper.montanaOffered.map { MTWallpaper.Choice.named($0) }
    }
    private var systemGrounds: [MTWallpaper.Choice] {
        var all = MTWallpaper.systemOffered.map { MTWallpaper.Choice.named($0) }
        if !task.isPage { all.insert(.general, at: 0) }
        return all
    }
    private func extraGround(_ now: MTWallpaper.Choice) -> MTWallpaper.Choice? {
        let offered = montanaGrounds + systemGrounds
        return offered.contains(now) ? nil : now
    }
    private func label(_ c: MTWallpaper.Choice) -> Text {
        switch c {
        case .general: return Text(task.isPage ? LocalizedStringKey("No background") : LocalizedStringKey("Same as my page"))
        case .named(let n): return Text(MTWallpaper.name(n))
        case .photo: return Text("Choose photo")
        }
    }
    /// The tile itself: the miniature, the check badge of the platform, and a touch shape over ALL of it. The photo worn now
    /// leads to the library tab; every other ground to the preview.
    private func tile(_ c: MTWallpaper.Choice, chosen: Bool) -> some View {
        Button {
            if case .photo = c { tab = 1 } else { preview = MTWallpaperCandidate(choice: c) }
        } label: { face(c, chosen: chosen) }
            .buttonStyle(.plain)
            .accessibilityLabel(label(c))
    }
    private func namedTile(_ c: MTWallpaper.Choice, chosen: Bool) -> some View {
        VStack(spacing: 7) {
            tile(c, chosen: chosen)
            label(c).font(.subheadline.weight(.medium)).frame(maxWidth: .infinity)
        }
    }
    private func face(_ c: MTWallpaper.Choice, chosen: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        return MTGroundMiniature(conv: conv, choice: c)
            .clipShape(shape)
            .overlay { shape.stroke(chosen ? Color.accentColor : Color.white.opacity(0.12), lineWidth: chosen ? 3 : 1) }
            .overlay(alignment: .bottomTrailing) {
                if chosen {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.white, Color.accentColor)
                        .padding(6)
                }
            }
            .contentShape(shape)   // the whole tile answers the finger (the author's word 22.09)
    }
}
/// A GROUND'S MINIATURE IS THE GROUND AS IT WILL STAND (the author's word 30.09: «the thumbnails must convey the page's ground
/// exactly»): the window's own frame scaled down -- the same drawing, the same crop -- and where the ground is worn softened
/// (my page's, MTSoftGround), the very softened picture the page will wear.
struct MTGroundMiniature: View {
    let conv: String
    let choice: MTWallpaper.Choice
    @ObservedObject private var book = MTWallpaper.Book.shared
    @State private var soft: UIImage?
    /// The page's choice the softened picture is made of, when this choice stands; nil where the ground is worn sharp.
    private var softened: MTWallpaper.Choice? {
        let page = conv == MTWallpaper.page ? choice : (choice == .general ? MTWallpaper.choice(for: MTWallpaper.page) : .general)
        return page == .general ? nil : page
    }
    var body: some View {
        let _ = book.rev
        let win = MTScene.size()
        let worn = softened
        Color.black
            .aspectRatio(max(win.width, 1) / max(win.height, 1), contentMode: .fit)
            .overlay {
                GeometryReader { g in
                    if worn == nil {
                        MontanaChatBackdrop(conv: conv, candidate: choice)
                            .frame(width: win.width, height: win.height)
                            .scaleEffect(g.size.width / max(win.width, 1), anchor: .topLeading)
                    } else if let soft {
                        Image(uiImage: soft).resizable().frame(width: g.size.width, height: g.size.height)
                    }
                }
            }
            .clipped()
            .task(id: String(describing: worn)) {
                guard let worn else { soft = nil; return }
                soft = await MTSoftGround.soft { MontanaChatBackdrop(conv: MTWallpaper.page, candidate: worn, sharp: true) }
            }
    }
}
struct MTWallpaperCandidate: Identifiable {
    let id = UUID()
    let choice: MTWallpaper.Choice
    var picture: UIImage? = nil   // a photo from the library: placed by the finger in the preview, saved as placed
}
/// THE PICTURE IS PLACED BY THE FINGER (the author's word 22.09: move it, size it, shrink it, set it as
/// it stands). The platform's own move-and-scale — a UIScrollView zooming its image view — inside a
/// container that draws BEHIND the picture the picture's own mirrored blur, the very dress a narrow photo
/// wears in a bubble (MessageBubble.mediaBubble: mirrored, blurred by 18, a fifth darkened). Shrunk to a
/// third, the picture stands anywhere on that dress; enlarged threefold, it is dragged by its own edges.
/// There is no editing panel of the platform to call here: the photo picker hands over the bytes and
/// nothing else, and no public screen of iOS crops for an app — so the move is the scroll view's, which
/// IS the platform's own (Gate −1b: the absence is named).
/// What the screen shows at the checkmark is exactly the wallpaper: this view's own snapshot, taken from the
/// screen at the window's size and pixel scale.
final class MTWallpaperCropView: UIView, UIScrollViewDelegate {
    private let scroll = UIScrollView()
    private let imageView = UIImageView()
    private let dress = UIImageView()
    private var fill: CGFloat = 0
    static let shrink: CGFloat = 0.33      // a third of the filling size — the picture may stand small
    static let blurRadius: CGFloat = 18    // the bubble's own number
    var image: UIImage? { didSet { imageView.image = image; dress.image = image.flatMap(Self.mirrorBlur); fill = 0; setNeedsLayout() } }
    /// The finger took the picture / the picture came to rest where the finger left it (the preview's two states).
    var onMove: (() -> Void)?
    var onSettle: (() -> Void)?
    init() {
        super.init(frame: .zero)
        backgroundColor = .black
        dress.contentMode = .scaleAspectFill
        dress.clipsToBounds = true
        addSubview(dress)
        scroll.delegate = self
        scroll.showsVerticalScrollIndicator = false; scroll.showsHorizontalScrollIndicator = false
        scroll.backgroundColor = .clear
        scroll.contentInsetAdjustmentBehavior = .never
        scroll.bouncesZoom = true
        imageView.contentMode = .scaleAspectFill
        scroll.addSubview(imageView)
        addSubview(scroll)
    }
    required init?(coder: NSCoder) { nil }
    /// The dress: the picture mirrored and blurred once, small — the image view enlarges it smoothly.
    private static func mirrorBlur(_ ui: UIImage) -> UIImage? {
        guard let cg = ui.cgImage else { return nil }
        let ci = CIImage(cgImage: cg)
            .transformed(by: CGAffineTransform(scaleX: -1, y: 1))
        guard let f = CIFilter(name: "CIGaussianBlur") else { return nil }
        f.setValue(ci.clampedToExtent(), forKey: kCIInputImageKey)
        f.setValue(max(6, ui.size.width / 40), forKey: kCIInputRadiusKey)
        guard let out = f.outputImage?.cropped(to: ci.extent),
              let made = CIContext().createCGImage(out, from: ci.extent) else { return nil }
        return UIImage(cgImage: made)
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        dress.frame = bounds
        scroll.frame = bounds
        guard let img = image, bounds.width > 1, bounds.height > 1, fill == 0 else { return }
        fill = max(bounds.width / max(img.size.width, 1), bounds.height / max(img.size.height, 1))
        let size = CGSize(width: img.size.width * fill, height: img.size.height * fill)
        scroll.zoomScale = 1
        imageView.frame = CGRect(origin: .zero, size: size)
        scroll.contentSize = size
        scroll.minimumZoomScale = Self.shrink; scroll.maximumZoomScale = 3
        // THE PICTURE GOES ANYWHERE (the author's word 22.09): the room around the content is a whole
        // screen on every side, so a shrunk picture is dragged into any corner and an enlarged one past
        // its own edges; the scroll view still owns the motion.
        scroll.contentInset = UIEdgeInsets(top: bounds.height, left: bounds.width, bottom: bounds.height, right: bounds.width)
        scroll.contentOffset = CGPoint(x: (size.width - bounds.width) / 2, y: (size.height - bounds.height) / 2)
        DispatchQueue.main.async { [weak self] in self?.onSettle?() }   // the first rest: the picture as it was laid
    }
    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) { onMove?() }
    func scrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?) { onMove?() }
    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) { if !decelerate { onSettle?() } }
    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) { onSettle?() }
    func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) { onSettle?() }
    /// WHAT THE SCREEN SHOWS, TAKEN FROM THE SCREEN (the author's word 23.09: «what the preview shows must stand on
    /// the chat's background byte for byte»). The picture used to be drawn here a second time by hand (the dress, a
    /// darkening of its own, the picture), and that second drawing is what the chat wore: T1's kept ground (05:02)
    /// stood on a flat grey sheet of 199 while the preview showed the mirrored blur. Now the platform's own snapshot
    /// of this very view (drawHierarchy) is kept, at this view's size and its window's pixels. A view not yet on the
    /// screen gives nothing rather than a black picture.
    func rendered() -> UIImage? {
        guard image != nil, window != nil, 1 < bounds.width, 1 < bounds.height else { return nil }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = traitCollection.displayScale   // this view's own window (the guard 22.09)
        format.opaque = true
        var shown = false
        let shot = UIGraphicsImageRenderer(bounds: bounds, format: format).image { _ in
            shown = drawHierarchy(in: bounds, afterScreenUpdates: true)
        }
        return shown ? shot : nil
    }
}
final class MTWallpaperCropHandle { weak var view: MTWallpaperCropView? }
struct MTWallpaperCrop: UIViewRepresentable {
    let image: UIImage
    let handle: MTWallpaperCropHandle
    var onMove: () -> Void = {}
    var onSettle: () -> Void = {}
    func makeUIView(context: Context) -> MTWallpaperCropView {
        let v = MTWallpaperCropView(); v.onMove = onMove; v.onSettle = onSettle; v.image = image; handle.view = v; return v
    }
    func updateUIView(_ v: MTWallpaperCropView, context: Context) {
        v.onMove = onMove; v.onSettle = onSettle
        if v.image !== image { v.image = image }
        handle.view = v
    }
}
/// The chat's background page, raised over everything (UIState.chatWall): the conversation it dresses.
struct MTWallOpen: Identifiable { let id: String }
/// THE PREVIEW IS ONE PAGE ([C-1], the author's word 22.09: one owner, called for different tasks).
/// The ground being tried stands full-screen — under the chat's own bubbles when a chat is being
/// dressed, under nothing when the pages are — the picture is placed by the finger, and the two marks
/// decide: the cross leaves everything as it was, the checkmark keeps the choice and the placement.
/// THE BLUR SLIDER HAS LEFT THIS PAGE (the author's word 23.09: «take the blur slider out of the
/// background's editing completely»): the ground stands here sharp, and the checkmark keeps it sharp.
enum MTWallpaperTask {
    case chat(String)
    /// My page's own ground, behind the face where the page does not scroll (the author's word 24.09).
    case page
    /// The ground this task dresses (MTWallpaper): a conversation's, or the page's own.
    var key: String {
        switch self {
        case .chat(let c): return c
        case .page: return MTWallpaper.page
        }
    }
    var isPage: Bool { if case .page = self { return true }; return false }
}
struct MTWallpaperPreview: View {
    let task: MTWallpaperTask
    let candidate: MTWallpaperCandidate
    /// A page hosted in the sliding container leaves by ITS OWN close; the system's dismiss has
    /// nothing to dismiss there (the page law, 19.09). Both are held: the page road uses the first.
    @Environment(\.montanaClose) private var close
    @Environment(\.dismiss) private var dismiss
    @State private var crop = MTWallpaperCropHandle()
    /// The placed picture at rest, rendered as the checkmark will keep it; nil while the finger moves it.
    @State private var settled: UIImage?
    @State private var moving = false
    private var conv: String { task.key }
    var body: some View {
        NavigationStack {
            ZStack {
                ground
                // THE PAGE'S GROUND STANDS WHOLE (the author's word 25.09: «on the preview page take away the crop that put the
                // photo into the top head alone; show it on the whole page»): the page's ground is every page's and every
                // chat's (rule 30), so the whole picture is what the person places -- nothing lit apart, nothing dimmed.
                if task.isPage {
                    // THE PAGE AS IT WILL STAND (the author's word 26.09: «the page ground's preview with the real face, name, bio,
                    // link, the write-on-the-wall button and an example post»): my own head over the whole picture, the wall's write
                    // button and one post -- the page's dress; the finger's is the picture's.
                    MTPagePreviewDress().allowsHitTesting(false)
                } else {
                    // THREE EXAMPLES AT THE TOP (the author's word 23.09): the chat's own bubbles over the ground, the
                    // words as they will stand — under the bar, where the eye starts; the picture stays free below.
                    VStack {
                        VStack(spacing: 7) {
                            MessageBubble(message: Message(text: String(localized: "Hello! This is the Montana style.", bundle: MTLanguage.bundle), isFromMe: false, time: nowHHMM()), player: VoicePlayer.shared)
                            MessageBubble(message: Message(text: String(localized: "Your message", bundle: MTLanguage.bundle), isFromMe: true, time: nowHHMM()), player: VoicePlayer.shared)
                            MessageBubble(message: Message(text: String(localized: "Their message", bundle: MTLanguage.bundle), isFromMe: false, time: nowHHMM()), player: VoicePlayer.shared)
                        }
                        .padding(.horizontal, 12).padding(.top, 8)
                        Spacer()
                    }
                    .allowsHitTesting(false)   // the bubbles are the picture's dress; the finger is the picture's
                }
            }
            .navigationTitle("Preview").navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { MontanaCloseMark { leave() } }
                ToolbarItem(placement: .topBarTrailing) { MontanaDoneMark { keep() } }
            }
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder private var ground: some View {
        if let ui = candidate.picture {
            ZStack {
                // Under the finger: the picture being placed (move and scale).
                MTWallpaperCrop(image: ui, handle: crop,
                                onMove: { moving = true },
                                onSettle: { settled = crop.view?.rendered(); moving = false })
                    .ignoresSafeArea()
                    .overlay(Color.black.opacity(0.25).ignoresSafeArea().allowsHitTesting(false))
                // At rest: THE CHAT'S OWN DRAWING of the placed picture — the very view the chat draws its
                // ground with, so what stands here at the checkmark is what the chat will wear.
                if !moving, let s = settled {
                    MontanaChatBackdrop(conv: conv, candidate: .general, candidatePicture: s)
                        .allowsHitTesting(false)
                }
            }
        } else {
            // A ground as the chat will wear it, drawn by the chat's own view.
            MontanaChatBackdrop(conv: conv, candidate: candidate.choice)
        }
    }

    private func leave() { mtLeavePage(close, dismiss) }
    /// THE CHECKMARK SETS THE GROUND, ALWAYS (the author's word 23.09: «I set a photo, set the blur, and the
    /// background did not change»; T1's own store: the softness written, no picture, the wallpapers folder
    /// empty). The picture was saved only through the placed rendering, and when that came back empty the
    /// checkmark left in silence after the softness had already been kept. Now the picture the person chose is
    /// always kept: the placed rendering when there is one, else the picture itself at the screen's size; and
    /// every outcome is named in the diary.
    private func keep() {
        var choice = candidate.choice
        if let ui = candidate.picture {
            var f: String? = nil
            var how = "placed"
            // THE PAGE'S GROUND IS KEPT LIGHT AT ONCE (the author's word 25.09): the placed rendering -- cropped to the window as
            // it stood -- compressed so the eye sees no loss, and so it travels as it lies; a chat's ground stays its lossless PNG.
            if let placed = settled ?? crop.view?.rendered() {
                f = task.isPage ? MTWallpaper.keep(MTWallpaper.lightData(placed)) : MTWallpaper.saveRendered(placed)   // what stood on the screen
            }
            if f == nil, let data = ui.jpegData(compressionQuality: 0.92) { f = MTWallpaper.savePhoto(data); how = "whole" }
            guard let file = f else {
                MontanaTrace.mark("wallpaper", "REFUSED — the picture could not be kept (placed=\(crop.view == nil ? 0 : 1))")
                return   // the page stays: nothing is set behind the person's back, and nothing is lost
            }
            choice = .photo(file)
            MontanaTrace.mark("wallpaper", "photo kept how=\(how) blur=0")
        } else {
            MontanaTrace.mark("wallpaper", "ground kept blur=0")
        }
        if case .photo(let old) = MTWallpaper.choice(for: conv), old != photoFile(choice) { MTWallpaper.remove(old) }
        MTWallpaper.setBlur(0, for: conv)   // no slider on this page: what is set is sharp, as the preview showed it
        MTWallpaper.set(choice, for: conv)
        if task.isPage { MTPageGround.changed() }   // my page's ground, to every correspondent who reads it (25.09)
        leave()
    }
    private func photoFile(_ c: MTWallpaper.Choice) -> String? { if case .photo(let f) = c { return f }; return nil }
}

/// MY PAGE OVER ITS GROUND, FOR THE PREVIEW (the author's word 26.09: «the page ground's preview with the real face, name, bio,
/// link, the write-on-the-wall button and an example post»): the head my page draws (MTFaceHeader at its circle) with my face, my
/// name as it leaves this phone, my words and my link as they leave it -- MontanaMyProfileView's own sources -- then the wall's
/// write button (MTBoardWriteFace, the wall's own drawing) and one post of my wall saying what it is (MTBoardCell). The dress
/// answers no finger: the picture under it is being placed.
struct MTPagePreviewDress: View {
    @AppStorage("avatarData") private var avatarData: Data = Data()
    @AppStorage("profileBio") private var bio: String = ""
    @AppStorage("profileLink") private var link: String = ""
    @StateObject private var face = MTFaceDock()
    private var sample: MTBoardSeen {
        MTBoardSeen(id: "preview", byName: E2E.myDisplayName(), byGlyph: E2E.myFaceGlyph(), at: Date().timeIntervalSince1970,
                    text: String(localized: "An example of a post on your page", bundle: MTLanguage.bundle), media: [],
                    pinned: false, keepers: 0, likes: 0, downloads: 0, reposts: 0, comments: [], commentCount: 0,
                    liked: false, kept: false, reposted: false, mine: true, own: true)
    }
    var body: some View {
        GeometryReader { g in
            VStack(spacing: 12) {
                MTFaceHeader(face: face, glyph: E2E.myFaceGlyph(), name: E2E.myDisplayName(), pageWidth: g.size.width,
                             bio: MTPeerAbout.said(bio), links: MTPeerAbout.links(link))
                MTBoardWriteFace().padding(.horizontal, MTPageEdge.side)
                MTBoardCell(post: sample, owner: nil, onComments: {}).padding(.horizontal, MTPageEdge.side)
                Spacer(minLength: 0)
            }
        }
        .onChange(of: avatarData, initial: true) { _, d in face.load(d) }
    }
}

/// THE APP'S ICON, CHOSEN BY ITS PICTURE (the author's word 26.09: «leave the icons to choose in the appearance settings»): the
/// platform's own alternate icons -- the primary (nil) the liquid glass document (AppIcon.icon), «AppIconGold» the gold on black --
/// each shown as its own miniature, the chosen one ringed in the platform's blue, the whole miniature the target. The platform itself
/// tells the person the icon changed; the diary says what was asked and what the platform answered.
struct MTAppIconChooser: View {
    struct Icon: Identifiable {
        let name: String?
        let preview: String
        let label: LocalizedStringKey
        var id: String { preview }
    }
    // SHA-256
    static let icons = [Icon(name: nil, preview: "IconGlassPreview", label: "Liquid glass"),
                        Icon(name: "AppIconGold", preview: "IconGoldPreview", label: "Gold on black"),
                        Icon(name: "AppIconSun", preview: "IconSunPreview", label: "Sunlight"),
                        Icon(name: "AppIconJuno", preview: "IconJunoPreview", label: "Juno"),
                        Icon(name: "AppIconPyramid", preview: "IconPyramidPreview", label: "Pyramid")]
    @State private var current = UIApplication.shared.alternateIconName
    var body: some View {
        HStack(spacing: 20) {
            ForEach(Self.icons) { icon in
                Button { choose(icon) } label: {
                    Image(icon.preview).resizable().scaledToFit()
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .stroke(current == icon.name ? MontanaOctagon.platformBlue : Color.clear, lineWidth: 3))
                        .padding(4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(icon.label))
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
    }
    private func choose(_ icon: Icon) {
        guard UIApplication.shared.supportsAlternateIcons, current != icon.name else { return }
        UIApplication.shared.setAlternateIconName(icon.name) { error in
            DispatchQueue.main.async {
                MontanaTrace.mark("app_icon", "set " + (icon.name ?? "primary") + (error == nil ? " ok" : " refused"))
                if error == nil { current = icon.name }
            }
        }
    }
}

struct AppearanceView: View {
    @AppStorage(MTLetterMotion.bounceKey) private var springBounce = MTLetterMotion.defaultBounce
    @AppStorage(MTLetterMotion.durationKey) private var springDuration = MTLetterMotion.defaultDuration
    @AppStorage("keyboardLook") private var keyboardLook: String = "system"
@AppStorage(MontanaSkin.key) private var skin = MontanaSkin.native.rawValue
    @AppStorage("bubbleStyle") private var bubbleStyle: String = "montana"
    @AppStorage(MontanaNoteQuality.key) private var noteQuality = MontanaNoteQuality.medium.rawValue
    @AppStorage("chatBg") private var chatBg: String = "default"
    @AppStorage("cbMineFill1") private var cbMineFill1 = BT.mF1
    @AppStorage("cbMineFill2") private var cbMineFill2 = BT.mF2
    @AppStorage("cbMineOpacity") private var cbMineOpacity = BT.mOp
    @AppStorage("cbMineText") private var cbMineText = BT.mTx
    @AppStorage("cbMineOutline") private var cbMineOutline = BT.mOl
    @AppStorage("cbMineOutlineOp") private var cbMineOutlineOp = BT.mOlOp
    @AppStorage("cbMineOutlineW") private var cbMineOutlineW = BT.mOlW
    @AppStorage("cbPeerFill1") private var cbPeerFill1 = BT.pF1
    @AppStorage("cbPeerFill2") private var cbPeerFill2 = BT.pF2
    @AppStorage("cbPeerOpacity") private var cbPeerOpacity = BT.pOp
    @AppStorage("cbPeerText") private var cbPeerText = BT.pTx
    @AppStorage("cbPeerOutline") private var cbPeerOutline = BT.pOl
    @AppStorage("cbPeerOutlineOp") private var cbPeerOutlineOp = BT.pOlOp
    @AppStorage("cbPeerOutlineW") private var cbPeerOutlineW = BT.pOlW
    @AppStorage("cbBgOn") private var cbBgOn = false
    @AppStorage("cbBgType") private var cbBgType = "gradient"
    @AppStorage("cbBg1") private var cbBg1 = BT.bg1
    @AppStorage("cbBg2") private var cbBg2 = BT.bg2
    @AppStorage(MTCoinShow.key) private var coinsShown = true   // read for the line that leads to Privacy (11.10)
    @State private var bgPhotoItem: PhotosPickerItem?
    @ObservedObject private var wallBook = MTWallpaper.Book.shared
    @State private var editor: ColEdit?

    enum CK { case mF1, mF2, mTx, mOl, pF1, pF2, pTx, pOl, bg1, bg2 }
    struct ColEdit: Identifiable { let id = UUID(); let title: LocalizedStringKey; let start: String; let key: CK; let apply: (String) -> Void }


    private static let keyOf: [CK: String] = [.mF1: "cbMineFill1", .mF2: "cbMineFill2", .mTx: "cbMineText", .mOl: "cbMineOutline",
                                              .pF1: "cbPeerFill1", .pF2: "cbPeerFill2", .pTx: "cbPeerText", .pOl: "cbPeerOutline",
                                              .bg1: "cbBg1", .bg2: "cbBg2"]
    /// THE PREVIEW IS THE CHAT (the author's word 11.09): the very bubbles the conversation draws,
    /// on the very ground it draws them on — one code, one picture, the person's own settings and
    /// nothing else. A second drawing of the bubble stood here and showed a look of its own. A
    /// colour still being chosen rides in BT.candidate, read through the same door as the stored one.
    private func previewStack(_ ov: CK? = nil, _ c: String? = nil) -> some View {
        if let ov, let c { BT.candidate = (Self.keyOf[ov]!, c) }
        let print = [skin, bubbleStyle, chatBg, cbMineFill1, cbMineFill2, "\(cbMineOpacity)", cbMineText, cbMineOutline,
                     "\(cbMineOutlineOp)", "\(cbMineOutlineW)", cbPeerFill1, cbPeerFill2, "\(cbPeerOpacity)", cbPeerText,
                     cbPeerOutline, "\(cbPeerOutlineOp)", "\(cbPeerOutlineW)", "\(cbBgOn)", cbBgType, cbBg1, cbBg2,
                     "\(MTBubbleGround.picture.count)", ov.map { "\($0)" } ?? "", c ?? ""].joined(separator: "|")
        return VStack(spacing: 7) {
            MessageBubble(message: Message(text: String(localized: "Their message", bundle: MTLanguage.bundle), isFromMe: false, time: nowHHMM()), player: VoicePlayer.shared)
            MessageBubble(message: Message(text: String(localized: "Your message", bundle: MTLanguage.bundle), isFromMe: true, time: nowHHMM()), player: VoicePlayer.shared)
        }
        .padding(.horizontal, 12).padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background(MontanaChatBackdrop())
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .id(print)
    }
    private func slider(_ title: LocalizedStringKey, _ value: Binding<Double>, _ range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundColor(.gray)
            Slider(value: value, in: range)
        }
    }
    // a color row that opens the in-app color editor (preview on top + Cancel/Save)
    private func colorRow(_ title: LocalizedStringKey, _ bind: Binding<String>, _ key: CK) -> some View {
        Button {
            editor = ColEdit(title: title, start: bind.wrappedValue, key: key, apply: { bind.wrappedValue = $0 })
        } label: {
            HStack {
                Text(title).foregroundColor(.primary)
                Spacer()
                RoundedRectangle(cornerRadius: 5).fill(Color(montanaHexString: bind.wrappedValue))
                    .frame(width: 30, height: 22)
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.white.opacity(0.3)))
            }
            .contentShape(Rectangle())   // the whole row is the target, not only its words (22.09)
        }
    }
    private func swapSides() {
        let f1=cbMineFill1, f2=cbMineFill2, op=cbMineOpacity, tx=cbMineText, oc=cbMineOutline, oo=cbMineOutlineOp, ow=cbMineOutlineW
        cbMineFill1=cbPeerFill1; cbMineFill2=cbPeerFill2; cbMineOpacity=cbPeerOpacity; cbMineText=cbPeerText
        cbMineOutline=cbPeerOutline; cbMineOutlineOp=cbPeerOutlineOp; cbMineOutlineW=cbPeerOutlineW
        cbPeerFill1=f1; cbPeerFill2=f2; cbPeerOpacity=op; cbPeerText=tx; cbPeerOutline=oc; cbPeerOutlineOp=oo; cbPeerOutlineW=ow
    }
    private func resetMontana() {
        cbMineFill1=BT.mF1; cbMineFill2=BT.mF2; cbMineOpacity=BT.mOp; cbMineText=BT.mTx; cbMineOutline=BT.mOl; cbMineOutlineOp=BT.mOlOp; cbMineOutlineW=BT.mOlW
        cbPeerFill1=BT.pF1; cbPeerFill2=BT.pF2; cbPeerOpacity=BT.pOp; cbPeerText=BT.pTx; cbPeerOutline=BT.pOl; cbPeerOutlineOp=BT.pOlOp; cbPeerOutlineW=BT.pOlW
        cbBgOn=false; cbBgType="gradient"; cbBg1=BT.bg1; cbBg2=BT.bg2; MTBubbleGround.clear()
    }
    var body: some View {
        VStack(spacing: 0) {
            previewStack()
                .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 4)
            List {
            Section("Application icons") {
                NavigationLink { MTLibraryIconStyleView() } label: {
                    HStack(spacing: 14) {
                        MTApplicationIcon(app: .chats, side: 48)
                        Text("Application icons").foregroundColor(.primary)
                    }
                }
            }.listRowBackground(MTGlassRowPlate())
            // THE APP'S ICON (the author's word 26.09): the liquid glass or the gold on black, chosen by their pictures.
            Section("App icon") {
                MTAppIconChooser()
            }.listRowBackground(MTGlassRowPlate())
            // 14.10.2026: reputation is mandatory; only the owner's balance can be hidden in Privacy.
            Section {
                Text("Your level is your reputation and is always visible. You can hide your balance in Privacy.")
                NavigationLink { PrivacyView() } label: {
                    LabeledContent { Text(coinsShown ? "On" : "Off") } label: { Text("Show my coins") }
                }
            } header: { Text("Balance and level at avatars") } footer: {
                Text("The level badge is red at the lowest reported level and green at the highest. Its color follows the current distribution of levels.")
            }.listRowBackground(MTGlassRowPlate())
            // The note's picture quality (the author's word 18.09): three steps, the platform's own
            // segmented picker — the source's height and the encoder's rate (MontanaNoteQuality).
            Section {
                Picker("Video note quality", selection: $noteQuality) {
                    Text("Min").tag(MontanaNoteQuality.low.rawValue)
                    Text("Medium").tag(MontanaNoteQuality.medium.rawValue)
                    Text("Max").tag(MontanaNoteQuality.high.rawValue)
                }.pickerStyle(.segmented).labelsHidden()
            } header: { Text("Video note quality") } footer: {
                Text("Max takes the camera's sharpest picture at the highest bitrate, Min makes the lightest file. A camera that cannot keep up steps down by itself.")
            }.listRowBackground(MTGlassRowPlate())
            // THE KEYS' LOOK (the author's word 21.09): the keys are drawn by the platform in its own
            // window and take no colour of ours — only their three looks. The panel around the field has
            // no ground to colour (the reference's clear panel).
            Section {
                Picker("Keys", selection: $keyboardLook) {
                    Text("System").tag("system")
                    Text("Dark").tag("dark")
                    Text("Light").tag("light")
                }.pickerStyle(.segmented)
            } header: { Text("Keyboard") } footer: {
                Text("How the keyboard looks while you write a message or search: as the system, always dark or always light.")
            }.listRowBackground(MTGlassRowPlate())
            Section {
                VStack(alignment: .leading) {
                    Text("Springiness")
                    Slider(value: $springBounce, in: MTLetterMotion.bounceRange)
                        .accessibilityLabel(Text("Springiness"))
                }
                VStack(alignment: .leading) {
                    Text("Animation duration")
                    Slider(value: $springDuration, in: MTLetterMotion.durationRange)
                        .accessibilityLabel(Text("Animation duration"))
                }
                Button("Reset motion") {
                    springBounce = MTLetterMotion.defaultBounce
                    springDuration = MTLetterMotion.defaultDuration
                }
            } header: { Text("Feed motion") } footer: {
                Text("Adjusts scrolling, new messages and the return after a reply swipe. Reduce Motion takes priority.")
            }.listRowBackground(MTGlassRowPlate())
            Section {
                Picker("Message style", selection: $bubbleStyle) {
                    Text("Montana (default)").tag("montana")
                    Text("Classic").tag("classic")
                    Text("Custom").tag("custom")
                }.pickerStyle(.inline).labelsHidden()
            } header: { Text("Message style") } footer: {
                Text("Montana: yours in the system blue, others' in grey. Classic: yours in your bubble colour, others' in dark grey. Custom: the colours you set below.")
            }.listRowBackground(MTGlassRowPlate())
            // The voice orb's own screen (the author's word 14.09): colours of both sides, the motion.
            Section("Voice message style") {
                NavigationLink { MontanaVoiceOrbStyleView() } label: {
                    HStack(spacing: 12) {
                        MontanaVoiceOrbBadge(animating: false, mine: false).frame(width: 34, height: 34)
                        Text("Voice message style").foregroundColor(.primary)
                    }
                }
            }.listRowBackground(MTGlassRowPlate())

            if bubbleStyle == "custom" {
                Section("Your bubble") {
                    colorRow("Fill top", $cbMineFill1, .mF1)
                    colorRow("Fill bottom", $cbMineFill2, .mF2)
                    slider("Fill opacity", $cbMineOpacity, BT.fillFloor...1.0)
                    colorRow("Text", $cbMineText, .mTx)
                    colorRow("Outline", $cbMineOutline, .mOl)
                    slider("Outline opacity", $cbMineOutlineOp, 0.0...1.0)
                    slider("Outline width", $cbMineOutlineW, 0.0...3.0)
                }.listRowBackground(MTGlassRowPlate())

                Section("Their bubble") {
                    colorRow("Fill top", $cbPeerFill1, .pF1)
                    colorRow("Fill bottom", $cbPeerFill2, .pF2)
                    slider("Fill opacity", $cbPeerOpacity, BT.fillFloor...1.0)
                    colorRow("Text", $cbPeerText, .pTx)
                    colorRow("Outline", $cbPeerOutline, .pOl)
                    slider("Outline opacity", $cbPeerOutlineOp, 0.0...1.0)
                    slider("Outline width", $cbPeerOutlineW, 0.0...3.0)
                }.listRowBackground(MTGlassRowPlate())

                Section {
                    Button { swapSides() } label: { Text("Swap sides").foregroundColor(.accentColor) }
                    Button { resetMontana() } label: { Text("Reset to Montana").foregroundColor(.accentColor) }
                }.listRowBackground(MTGlassRowPlate())
            }
            // THE PAGES HAVE NO GROUND TO CHOOSE (the author's word 23.09: «remove the pages' background from
            // Appearance completely»): they stand on the crest; a chat's ground is chosen in the chat itself.
            }
            .scrollContentBackground(.hidden)
        }
        .montanaPageGround()   // my page's ground, as the drawer and my page wear it (25.09)
        .navigationTitle("Appearance").navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .sheet(item: $editor, onDismiss: { BT.candidate = nil }) { e in
            ColorEditorSheet(title: e.title, start: e.start,
                             preview: { c in AnyView(previewStack(e.key, c.montanaHex()).padding(.horizontal, 8)) },
                             onSave: { e.apply($0) })
        }
    }
}

/// THE COLOUR IS CHOSEN ON THE SYSTEM'S OWN PICKER (the author's word 19.09): the native colour row
/// opens the platform's picker — grid, spectrum, sliders, eyedropper — risen and fitted by the
/// system itself on any device and any firmware; the sheet keeps the live preview above the row
/// and lands the change only on the checkmark (the appearance-editing contract).
struct ColorEditorSheet: View {
    let title: LocalizedStringKey
    let start: String
    let preview: (Color) -> AnyView
    let onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var cand: Color = .gray
    var body: some View {
        NavigationStack {
            List {
                Section {
                    preview(cand).padding(.vertical, 8)
                }.listRowBackground(MTGlassRowPlate())
                Section {
                    ColorPicker("Colour", selection: $cand, supportsOpacity: false).foregroundColor(.primary)
                    // USER-DATA: the colour's hex number.
                    Text(verbatim: "#" + cand.montanaHex()).font(.system(.footnote, design: .monospaced)).foregroundColor(.gray)
                }.listRowBackground(MTGlassRowPlate())
            }
            .scrollContentBackground(.hidden)
            .montanaPageGround()   // my page's ground, as every page wears it (26.09)
            .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { MontanaCloseMark { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { MontanaDoneMark { onSave(cand.montanaHex()); dismiss() } }
            }
            .onAppear { cand = Color(montanaHexString: start) }
        }
        .preferredColorScheme(.dark)
    }
}

struct DataStorageView: View {
    @AppStorage("autoDownloadCellular") private var autoCellular = true
    @AppStorage("autoDownloadWiFi") private var autoWiFi = true
    @AppStorage(MontanaBackupCloud.switchKey) private var cloudOn = false
    @State private var cloudReady = false
    @State private var working = false
    @State private var picking = false
    @State private var asking = false
    @State private var tally: MontanaBackup.Tally? = nil
    @State private var word: LocalizedStringKey? = nil
    @ObservedObject private var cloud = CloudWatch.shared     // what iCloud holds, answered by iCloud alone; one per process
    @State private var replacing = false                      // the person's own «replace the copy iCloud holds»
    @ObservedObject private var copying = CloudCopy.shared    // the copy being sealed for iCloud, our own count
    @State private var previewing = false                     // the copy before it is made
    @State private var restoring: Double? = nil               // a copy being taken back: the share of its frames filed
    @State private var unmet = false                          // iCloud holds a copy this device has not taken back
    @State private var inventory: CopyInventory? = nil        // what this device holds, counted
    /// The pages below change what they count (a file deleted from its chat); they write back here.
    private func held(_ inv: CopyInventory) -> Binding<CopyInventory> {
        Binding(get: { inventory ?? inv }, set: { inventory = $0 })
    }
    @State private var plan = CopyPlan.load()                 // what the person left out
    @State private var picturesCleared = false
    @State private var disk: MTDiskUse? = nil                 // what this phone holds, measured on its disk (MTDiskUse)
    @State private var clearingShelf = false
    @State private var releasing = false   // the person's word on the opened files left behind (MTDocLink.release)
    @ObservedObject private var homeKeep = MTHomeKeep.shared   // the files on the person's own node, in the node's own word (18.10)
    @State private var clearingCache = false
    @State private var cacheWord: LocalizedStringKey? = nil
    @AppStorage(MTHomeKeep.keepDaysKey) private var keepDays = 0
    @AppStorage(MTHomeKeep.limitKey) private var cacheLimit = 0
    private func measureDisk(_ inv: CopyInventory) {
        let named = Set(inv.owner.keys)
        DispatchQueue.global(qos: .utility).async {
            let u = MTDiskUse.measure(named: named)
            DispatchQueue.main.async { disk = u }
        }
    }
    private func diskRow(_ title: LocalizedStringKey, _ icon: String, _ color: Color, _ bytes: Int64) -> some View {
        HStack {
            settingsToggleLabel(title, icon, color)
            Spacer()
            Text(verbatim: mtSize(Int(bytes))).foregroundColor(.secondary)   // USER-DATA: a size measured on this phone
        }
    }

    var body: some View {
        List {
            Section {
                Toggle(isOn: $autoCellular) {
                    settingsToggleLabel("Over mobile network", "antenna.radiowaves.left.and.right", .green)
                }
                Toggle(isOn: $autoWiFi) {
                    settingsToggleLabel("Over Wi-Fi", "wifi", .blue)
                }
            } header: {
                Text("MEDIA AUTO-DOWNLOAD")
            } footer: {
                Text("When off, an attachment shows a download button and is fetched on tap.")
            }
            .listRowBackground(MTGlassRowPlate())

            Section {
                Button {
                    let n = MontanaCaches.dropAll(why: "clear")
                    MontanaTrace.mark("caches", "cleared=\(n) by=person")
                    picturesCleared = true
                } label: {
                    HStack {
                        settingsToggleLabel("Clear", "photo.on.rectangle.angled", .gray)
                        Spacer()
                        if picturesCleared { Image(systemName: "checkmark").foregroundColor(.secondary) }
                    }
                    .contentShape(Rectangle())
                }
            } header: {
                Text("PICTURE CACHE")
            } footer: {
                Text("Pictures are kept in memory so chats and walls open without waiting. They stay until you clear them here.")
            }
            .listRowBackground(MTGlassRowPlate())

            // THE CACHE, CLEARED AS THE REFERENCE CLEARS IT (the author's word 18.10.2026 17:1x UTC): what the person's own node
            // holds leaves this phone, and comes back from the node at a look or a tap -- the node's word decides, asked anew.
            Section {
                if case .held(let files, let bytes, _) = homeKeep.word {
                    HStack {
                        settingsToggleLabel("Kept on your node", "externaldrive.fill", .gray)
                        Spacer()
                        Text(verbatim: String(files) + " · " + mtSize(bytes)).foregroundColor(.secondary)   // USER-DATA: the node's count and size
                    }
                }
                Button { clearingCache = true } label: {
                    HStack {
                        settingsToggleLabel("Clear cache", "trash.fill", .red)
                        Spacer()
                        if homeKeep.clearing { ProgressView() }
                    }
                    .contentShape(Rectangle())
                }
                .disabled(!MTHomeShelf.bringing || homeKeep.clearing)
                // AS THE REFERENCE KEEPS ITS CACHE: a term for what nobody opened, a ceiling for the whole -- what leaves is what
                // the node holds, asked anew.
                VStack(alignment: .leading, spacing: 4) {
                    Picker(selection: $keepDays) {
                        Text("3 days").tag(3)
                        Text("1 week").tag(7)
                        Text("1 month").tag(30)
                        Text("Forever").tag(0)
                    } label: { settingsToggleLabel("Keep media", "clock.arrow.circlepath", .blue) }
                    .disabled(!MTHomeShelf.bringing)
                    .onChange(of: keepDays) { _, _ in homeKeep.trim() }
                    Text("A photo, video or file your node holds leaves this phone when nobody has opened it for this long. It comes back from your node when you open it.")
                        .font(.caption).foregroundColor(.gray)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Picker(selection: $cacheLimit) {
                        ForEach([5, 16, 32], id: \.self) { g in
                            Text(verbatim: mtSize(g * 1_073_741_824)).tag(g)   // USER-DATA: a size in the platform's own units
                        }
                        Text("No limit").tag(0)
                    } label: { settingsToggleLabel("Maximum cache size", "internaldrive.fill", .gray) }
                    .disabled(!MTHomeShelf.bringing)
                    .onChange(of: cacheLimit) { _, _ in homeKeep.trim() }
                    Text("Past this size the files opened longest ago leave this phone first, only those your node holds.")
                        .font(.caption).foregroundColor(.gray)
                }
            } header: {
                Text("CACHE")
            } footer: {
                Text(MTHomeShelf.bringing
                     ? "What your node holds leaves this phone. Each photo, video and file comes back from your node when you open it, here or on a new phone with your 24 words."
                     : "Set up your node in Settings, Your node: what it holds can then be cleared from this phone and comes back when you open it.")
            }
            .listRowBackground(MTGlassRowPlate())
            .confirmationDialog("Clear the cache?", isPresented: $clearingCache, titleVisibility: .visible) {
                Button("Clear", role: .destructive) {
                    homeKeep.clear { r in
                        if let r { cacheWord = "Cleared from this phone: \(r.files) files, \(mtSize(r.bytes)). Your node keeps them." }
                        else { cacheWord = "Your node did not answer. Nothing was cleared." }
                        if let inv = inventory { measureDisk(inv) }
                    }
                }
            } message: {
                Text("Only what your node holds leaves this phone; what it does not hold stays.")
            }
            .alert("Cache", isPresented: Binding(get: { cacheWord != nil }, set: { if !$0 { cacheWord = nil } })) {
                Button("OK") { cacheWord = nil }
            } message: {
                if let w = cacheWord { Text(w) }
            }

            // WHAT THIS PHONE HOLDS, MEASURED ON ITS DISK (the author's word 18.10.2026 07:2x UTC: «on T1 Montana weighs 20 GB, I cannot
            // see what weighs so much nor how to clean it, and Data and Storage shows other numbers»): the sum is the phone's own, each
            // file counted once; the attachments are chosen by kind below, the waiting copies cleared here.
            Section {
                if let u = disk {
                    NavigationLink { CopyKindsPage(inventory: held(inventory ?? CopyInventory()), plan: $plan) } label: {
                        diskRow("Attachments of chats", "paperclip", .indigo, u.chats)
                    }
                    NavigationLink { CopyKindsPage(inventory: held(inventory ?? CopyInventory()), plan: $plan) } label: {
                        diskRow("Files no letter names", "doc.badge.ellipsis", .gray, u.unnamed)
                    }
                    diskRow("Pictures of walls", "square.grid.2x2.fill", .teal, u.walls)
                    HStack {
                        diskRow("Copies waiting on this phone", "shippingbox.fill", .orange, u.shelf)
                        Button { clearingShelf = true } label: {
                            Image(systemName: "trash").foregroundColor(.red)
                                .frame(width: 44, height: 44).contentShape(Rectangle())
                        }
                        .buttonStyle(.borderless)
                        .disabled(u.shelf == 0)
                        .accessibilityLabel(Text("Clear"))
                    }
                    diskRow("Kept for the people who write to you", "person.2.fill", .green, u.kept)
                    // EVERY PART NAMED AND EACH IN THE PERSON'S HAND (the author's word 18.10.2026 20:3x UTC): the links a viewer was
                    // handed that outlived their files are released by one word (MTDocLink.release) -- what the node does not hold
                    // goes back to the chats, never lost; the history is the letters themselves, cleared chat by chat.
                    HStack {
                        diskRow("Opened files", "doc.on.doc.fill", .purple, u.opened)
                        Button { releasing = true } label: {
                            Image(systemName: "trash").foregroundColor(.red)
                                .frame(width: 44, height: 44).contentShape(Rectangle())
                        }
                        .buttonStyle(.borderless)
                        .disabled(u.opened == 0)
                        .accessibilityLabel(Text("Clear"))
                    }
                    diskRow("History of chats", "clock.fill", .blue, u.history)
                    diskRow("Faces", "person.crop.circle.fill", .pink, u.faces)
                    diskRow("The rest", "ellipsis.circle.fill", .gray, u.other)
                    HStack {
                        Text("On this phone").fontWeight(.semibold)
                        Spacer()
                        Text(verbatim: mtSize(Int(u.total))).fontWeight(.semibold)   // USER-DATA: the sum measured on this phone
                    }
                } else {
                    ProgressView().frame(maxWidth: .infinity)
                }
            } header: {
                Text("ON THIS PHONE")
            } footer: {
                Text("Measured on this phone's disk, each file once. Attachments and files no letter names are chosen by kind: select all of a kind and delete them.")
            }
            .listRowBackground(MTGlassRowPlate())
            .confirmationDialog("Clear the copies waiting on this phone?", isPresented: $clearingShelf, titleVisibility: .visible) {
                Button("Clear", role: .destructive) {
                    MontanaArchive.onOwnQueue {
                        MontanaBackup.sweep(all: true)
                        DispatchQueue.main.async { if let inv = inventory { measureDisk(inv) } }
                    }
                }
            } message: {
                Text("The copies and their shares made for iCloud, your node and your keepers leave this phone; the next round makes them again.")
            }
            .confirmationDialog("Clear opened files?", isPresented: $releasing, titleVisibility: .visible) {
                Button("Clear", role: .destructive) {
                    Task { @MainActor in
                        let r = await MTDocLink.release()
                        cacheWord = "Freed \(mtSize(Int(r.freed))). Files back in your chats: \(r.back)."
                        if let inv = inventory { measureDisk(inv) }
                    }
                }
            } message: {
                Text("Copies a viewer was handed when you opened a file. A file your node holds leaves; one it does not hold yet goes back to your chats for your node. Videos of other people's walls leave too: their walls keep them, not your node.")
            }

            Section {
                Toggle(isOn: cloudSwitch) {
                    settingsToggleLabel("iCloud", "icloud.fill", .blue)
                }
                .disabled(working)
                // WHAT IS BEING SEALED FOR iCLOUD, under the iCloud row itself and from its first moment (the
                // author, 23.09 18:27) — this phone's own count, and its words say so.
                if let f = copying.sealing {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Sealing the copy for iCloud").foregroundColor(.primary)
                            Spacer()
                            Text(verbatim: String(Int(f * 100)) + "%").foregroundColor(.secondary)   // USER-DATA: a share
                        }
                        ProgressView(value: f)
                    }
                    .padding(.vertical, 4)
                }
                // A COPY COMING BACK FROM iCLOUD, in iCloud's own count; only the person stops it (the critic, 23.09).
                if let fetch = cloud.fetching {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            switch fetch {
                            case .coming(let f):
                                Text("Downloading from iCloud").foregroundColor(.primary)
                                Spacer()
                                if let f { Text(verbatim: String(Int(f * 100)) + "%").foregroundColor(.secondary) }   // USER-DATA: a share
                            case .waiting(let why):
                                Text("Waiting for iCloud").foregroundColor(.primary)
                                Spacer()
                                Text(verbatim: why).font(.footnote).foregroundColor(.secondary)   // USER-DATA: iCloud's code
                            }
                            Button { cloud.cancelFetch() } label: {
                                Image(systemName: "xmark.circle.fill").font(.title3).foregroundColor(.secondary)
                                    .frame(width: 44, height: 44).contentShape(Rectangle())
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel(Text("Stop"))
                        }
                        if case .coming(let f?) = fetch { ProgressView(value: f) }
                    }
                    .padding(.vertical, 4)
                }
                // WHAT iCLOUD HOLDS, IN iCLOUD'S OWN WORDS (the author, 23.09 01:50): a file handed to the
                // container on this phone is not a file in the cloud. Uploaded, uploading with its share,
                // or refused — nothing else is ever said here, and nothing is read from this phone's disk.
                switch cloud.state {
                case .none:
                    EmptyView()
                case .held(let d, let b):
                    HStack {
                        Text("In iCloud").foregroundColor(.primary)
                        Spacer()
                        Text(verbatim: d.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened, locale: MTLanguage.locale)) + " · " + mtSize(b)).foregroundColor(.secondary)   // USER-DATA: a moment and a size
                    }
                case .sending(let f, _, let b):
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Uploading to iCloud").foregroundColor(.primary)
                            Spacer()
                            Text(verbatim: (f.map { String(Int($0 * 100)) + "% · " } ?? "") + mtSize(b)).foregroundColor(.secondary)   // USER-DATA: a share and a size
                        }
                        if let f { ProgressView(value: f) }
                    }
                    .padding(.vertical, 4)
                case .waiting(let why, _, let b):
                    // NOT A REFUSAL (23.09, iPhone 17 on mobile data): iCloud did not reach its servers
                    // and goes on by itself; the words say so, and nothing here is painted as an error.
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Waiting for iCloud").foregroundColor(.primary)
                            Spacer()
                            Text(verbatim: mtSize(b)).foregroundColor(.secondary)   // USER-DATA: a size
                        }
                        Text("iCloud could not reach its servers (\(why)). It continues on its own once connected; on mobile data it may wait for Wi-Fi.")
                            .font(.footnote).foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                case .signIn(let why):
                    Text("iCloud asks you to sign in to your Apple Account again: Settings, your name (\(why)).").foregroundColor(.primary)
                case .driveOff(let why):
                    Text("iCloud Drive is off on this device: Settings, your name, iCloud, iCloud Drive (\(why)).").foregroundColor(.primary)
                case .noRoom(_, let b):
                    VStack(alignment: .leading, spacing: 8) {
                        Text("iCloud has no room for the new copy (\(mtSize(b))) next to the one it holds.").foregroundColor(.red)
                        if cloud.kept != nil {
                            Button { replacing = true } label: { Text("Replace the copy in iCloud") }
                        }
                    }
                    .padding(.vertical, 4)
                case .refused(let why, _):
                    Text("iCloud refused the upload: \(why)").foregroundColor(.red)
                }
                // THE COPY iCLOUD STILL HOLDS while a newer one is on its way or refused — iCloud's own word too.
                if let k = cloud.kept {
                    HStack {
                        Text("Previous copy in iCloud").foregroundColor(.primary)
                        Spacer()
                        Text(verbatim: k.date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened, locale: MTLanguage.locale)) + " · " + mtSize(k.bytes)).foregroundColor(.secondary)   // USER-DATA: a moment and a size
                    }
                }
            } header: {
                Text("SYNC")
            } footer: {
                Text("Once a day while Montana is open, a copy of your history goes to the iCloud storage of your Apple Account, sealed with the key your 24 words open. The words are not in it. You find it where every app keeps its copy: Settings, your name, iCloud, Storage, Montana. Apple sees a file, its size and the moment it was written, and nothing else.")
            }
            .listRowBackground(MTGlassRowPlate())

            Section {
                Button { make() } label: {
                    HStack {
                        settingsToggleLabel("Create backup…", "arrow.up.doc.fill", .green)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .disabled(working)
                Button { asking = true } label: {
                    HStack {
                        settingsToggleLabel("Restore from backup…", "arrow.down.doc.fill", .orange)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .disabled(working)
                // A COPY COMING BACK, under the row that started it and from its first frame (the critic, 23.09: a
                // spinner stood on «Create backup» while 2.9 GB came back with no bar at all). The copy's own frames
                // read and filed — this phone's own count.
                if let f = restoring {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Restoring from the backup").foregroundColor(.primary)
                            Spacer()
                            Text(verbatim: String(Int(f * 100)) + "%").foregroundColor(.secondary)   // USER-DATA: a share
                        }
                        ProgressView(value: f)
                    }
                    .padding(.vertical, 4)
                }
                // WHAT THE COPY TAKES, COUNTED FROM THIS DEVICE — and every row opens what is inside
                // (the author, 23.09 01:31). Conversations and their letters on one page, attachments
                // by kind on the other; a mark on a row says whether the copy takes it.
                if let inv = inventory {
                    let now = inv.taken(plan)
                    NavigationLink { CopyChatsPage(inventory: inv, plan: $plan) } label: {
                        HStack {
                            settingsToggleLabel("Conversations", "bubble.left.and.bubble.right.fill", .blue)
                            Spacer()
                            Text("\(now.chats) / \(inv.convs.count)").foregroundColor(.secondary)
                        }
                    }
                    NavigationLink { CopyChatsPage(inventory: inv, plan: $plan) } label: {
                        HStack {
                            settingsToggleLabel("Records", "text.alignleft", .teal)
                            Spacer()
                            Text("\(now.letters)").foregroundColor(.secondary)
                        }
                    }
                    NavigationLink { CopyKindsPage(inventory: held(inv), plan: $plan) } label: {
                        HStack {
                            settingsToggleLabel("Attachments", "paperclip", .indigo)
                            Spacer()
                            Text("\(now.files) · \(mtSize(now.bytes))").foregroundColor(.secondary)
                        }
                    }
                }
            } header: {
                Text("BACKUP")
            } footer: {
                Text("A backup holds every conversation and attachment this device keeps, sealed with the key your 24 words open. Keep the words: without them nobody can read it, and neither can you.")
            }
            .listRowBackground(MTGlassRowPlate())
            MTKeepingSection()   // the copy kept by the people one writes to (MTKeeping, 08.10)
        }
        .scrollContentBackground(.hidden)
        .montanaPageGround()   // my page's ground, as the drawer and my page wear it (25.09)
        .navigationTitle("Data and Storage")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: plan) { _, p in p.save() }
        .onAppear {
            CopyInventory.gather { inv in inventory = inv; measureDisk(inv) }
            homeKeep.ask()
            MontanaBackupCloud.ready { r in
                cloudReady = r
                if r { cloud.start() }
            }
        }
        .confirmationDialog("Replace the copy in iCloud?", isPresented: $replacing, titleVisibility: .visible) {
            Button("Replace", role: .destructive) { cloud.replaceKept() }
            Button("Always replace", role: .destructive) { cloud.replaceKept(always: true) }
        } message: {
            Text("The copy iCloud holds is deleted first. Until the new one is uploaded, iCloud holds no copy; your history stays on this device.")
        }
        .sheet(isPresented: $previewing) {
            if let inv = inventory {
                CopyPreviewSheet(inventory: held(inv), plan: $plan) { r in
                    switch r {
                    case .success(let m):
                        tally = m.tally
                        // The sheet is lowering: the share sheet rises after it, not over it.
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { MTShare.present([m.url]) }
                    case .failure(let e):
                        word = say(e)
                    }
                }
            }
        }
        .fileImporter(isPresented: $picking, allowedContentTypes: [.data], allowsMultipleSelection: false) { r in take(r) }
        .alert("Backup", isPresented: Binding(get: { word != nil }, set: { if !$0 { word = nil } })) {
            Button("OK") { word = nil }
        } message: {
            if let w = word { Text(w) }
        }
        // A DEVICE THAT HAS NOT TAKEN ITS COPY BACK IS ASKED, NEVER OVERWRITTEN (the critic, 23.09): turning iCloud
        // on first on a new phone used to seal the empty app, and once iCloud held it the real copy left.
        .alert("iCloud holds your copy", isPresented: $unmet) {
            if cloud.url != nil { Button("Restore it") { fromCloud() } }
            Button("Begin anew", role: .destructive) {
                MontanaBackupCloud.beginAnew()
                CopyInventory.tickNow(urgent: true) { _ in CopyInventory.gather { inventory = $0 } }
            }
            Button("Later", role: .cancel) {}
        } message: {
            Text("This device has not taken back the copy iCloud holds. Restore it now — a new copy made from this device would take its place in iCloud.")
        }
        // A RESTORE HANDS THIS DEVICE THE RIGHT TO ANSWER (the critic, 23.09): the head of a
        // conversation carries the secret of the pipe, so the phone that takes a copy becomes a full
        // correspondent of every conversation in it. That is said before the act, not discovered after.
        .alert("Restore from backup?", isPresented: $asking) {
            // The copy in the cloud is taken back from inside the app, the way the platform's own
            // copies are; a copy saved by hand anywhere else is picked as a file.
            if cloud.url != nil { Button("From iCloud") { fromCloud() } }
            Button(cloud.url == nil ? LocalizedStringKey("Continue") : LocalizedStringKey("From a file")) { picking = true }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The conversations and attachments from the backup are merged into this device — nothing here is erased. This device will then answer for those conversations as your own phone does.")
        }
    }

    /// The switch obeys the cloud, not the wish: with no container on this build and no iCloud Drive
    /// under this person, it does not turn on and says why. A switch standing on while nothing travels
    /// is the same lie as a progress bar over an empty road.
    private var cloudSwitch: Binding<Bool> {
        Binding(get: { cloudOn && cloudReady },
                set: { v in
                    guard cloudReady else {
                        word = "iCloud Drive is not available here. Sign in to iCloud, turn iCloud Drive on, and try again."
                        return
                    }
                    guard v else { cloudOn = false; return }
                    // THE SWITCH ASKS THE ONE ROAD, IT DOES NOT BUILD A COPY OF ITS OWN (the author, 23.09
                    // 18:27: «why does it do the work twice?» — at 18:24 it sealed a second 2.9 GB copy while
                    // iCloud was taking the one of 18:06). It turns the copies on and asks the daily tick to
                    // run now: a copy is made only if one is due and nothing is on its way, and what is
                    // sealed shows under this row from its first moment. A refusal of the engine turns it
                    // back off with the words (the author, 23.09 00:24: the switch follows the fact).
                    cloudOn = true
                    MontanaBackupCloud.ready { r in if r { cloud.start() } }
                    cloud.whenAnswered {
                        CopyInventory.tickNow(urgent: true) { outcome in
                            if case .refused(let e) = outcome {
                                if case .stopped = e {} else { cloudOn = false; word = say(e) }
                            }
                            if case .unmet = outcome { unmet = true }
                            CopyInventory.gather { inventory = $0 }
                        }
                    }
                })
    }

    /// THE SCOPE IS READ FROM A FRESH COUNT, EVERY TIME (the critic, 23.09): a copy started before
    /// the inventory arrived used to take everything — including a conversation the person had left
    /// out. The count is taken first, the copy follows it; there is no road to the engine around it.
    private func withScope(_ go: @escaping (MontanaBackup.Scope) -> Void) {
        CopyInventory.gather { inv in
            inventory = inv
            go(inv.scope(plan))
        }
    }

    /// «Create backup» opens the copy BEFORE it is made (the author, 23.09 01:50): what it takes by kind,
    /// each kind opening its files, then the checkmark, then the bar. The count is taken fresh first.
    private func make() {
        CopyInventory.gather { inv in
            inventory = inv
            previewing = true
        }
    }

    private func take(_ r: Result<[URL], Error>) {
        guard case .success(let urls) = r, let u = urls.first else { return }
        working = true
        restoring = 0
        MontanaBackup.restore(from: u, progress: { restoring = $0 }) { res in
            working = false
            restoring = nil
            switch res {
            case .success(let t):
                tally = t
                afterTaking(u)
                word = "Taken into this device: \(t.chats) conversations, \(t.records) records, \(t.media) attachments."; CopyInventory.gather { inventory = $0 }
            case .failure(let e):
                word = say(e)
            }
        }
    }

    private func fromCloud() {
        guard let u = cloud.url else { return }
        working = true
        cloud.fetch(u) { r in
            switch r {
            case .failure(let e):
                working = false
                if case .stopped = e { return }
                word = say(e)
            case .success(let url):
                restoring = 0
                MontanaBackup.restore(from: url, progress: { restoring = $0 }) { res in
                    working = false
                    restoring = nil
                    switch res {
                    case .success(let t):
                        tally = t
                        afterTaking(url)
                        word = "Taken into this device: \(t.chats) conversations, \(t.records) records, \(t.media) attachments."; CopyInventory.gather { inventory = $0 }
                    case .failure(let e):
                        word = say(e)
                    }
                }
            }
        }
    }

    /// The copy just taken back is this device's last copy; the switch it carried is standing again, so the
    /// daily copy wakes by the one road — and finds nothing due until a day after the copy was made.
    private func afterTaking(_ url: URL) {
        MontanaBackupCloud.tookBack(url)
        if cloudOn { CopyInventory.tickSoon() }
    }

    private func report(_ r: Result<MontanaBackup.Tally, MontanaBackup.Refusal>) {
        switch r {
        case .success(let t): tally = t
        case .failure(let e): word = say(e)
        }
    }

    /// Every refusal is spoken, and the words distinguish what a person must do next. A copy made
    /// under another phrase is not a damaged copy, and saying so is how the only copy gets deleted.
    private func say(_ e: MontanaBackup.Refusal) -> LocalizedStringKey {
        switch e {
        case .noSeed: return "This device holds no identity yet. Enter your 24 words first, then restore."
        case .noVault: return "The storage of this device did not open just now. Try again in a moment."
        case .noEntropy: return "The core refused to draw randomness. Try again in a moment."
        case .noSpace: return "The disk has no room left. Free some space and try again."
        case .stopped: return "Stopped."
        case .diskRefused(let why): return "The disk refused: \(why)"
        case .cloudRefused(let why): return "iCloud did not take the copy: \(why)"
        case .empty: return "There is nothing to copy yet."
        case .notOurs: return "This file is not a Montana backup."
        case .version: return "This backup was made by a newer version of Montana."
        case .wrongWords: return "These 24 words do not open this backup: it belongs to another phrase."
        case .unopened: return "These 24 words do not open this file: it is a backup of another phrase, or not a Montana backup at all."
        case .torn: return "This backup is cut short or damaged. Whatever could be read has been filed."
        }
    }
}


@ViewBuilder
func settingsToggleLabel(_ title: LocalizedStringKey, _ icon: String, _ color: Color) -> some View {
    HStack(spacing: 12) {
        Image(systemName: icon)
            .font(.system(size: 15, weight: .semibold))
            .foregroundColor(.white)
            .frame(width: 29, height: 29)
            .background(color)
            .clipShape(RoundedRectangle(cornerRadius: 7))
        Text(title).foregroundColor(.primary)
    }
}

/// THE PHOTOS AND THE CONTACTS AS iOS KEEPS THEM (the author's word 24.09: «under the location put the road to
/// this access too; after the photos, the contacts with their road and their state -- exactly what is set in
/// iOS»). The word is the one the system's own page for this app shows, read from the system at the moment it
/// is asked; the privacy page asks again on every return to the app. The tap is the location row's one tap: a
/// permission never asked is asked here, one already decided is changed where the system keeps it.
enum MTSystemAccess {
    static var refused: Bool {
        let media = [AVCaptureDevice.authorizationStatus(for: .video), AVCaptureDevice.authorizationStatus(for: .audio)]
        let contacts = CNContactStore.authorizationStatus(for: .contacts)
        let photos = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        return media.contains { $0 == .denied || $0 == .restricted }
            || contacts == .denied || contacts == .restricted || photos == .denied || photos == .restricted
    }

    static var photosWord: String {
        switch PHPhotoLibrary.authorizationStatus(for: .readWrite) {
        case .authorized: return "Full Access"
        case .limited: return "Limited Access"
        case .denied: return "None"
        case .restricted: return "Restricted"
        case .notDetermined:
            // The saving road may have been let in alone: the system's page names it so.
            return PHPhotoLibrary.authorizationStatus(for: .addOnly) == .authorized ? "Add Photos Only" : "Not asked"
        @unknown default: return "Not asked"
        }
    }
    static var contactsWord: String {
        let st = CNContactStore.authorizationStatus(for: .contacts)
        if #available(iOS 18, *) {
            // From iOS 18 the system keeps three answers for the contacts, as for the photos.
            switch st {
            case .authorized: return "Full Access"
            case .limited: return "Limited Access"
            case .denied: return "None"
            case .restricted: return "Restricted"
            case .notDetermined: return "Not asked"
            @unknown default: return "Not asked"
            }
        }
        // Before iOS 18 the system's page keeps a switch.
        switch st {
        case .authorized: return "Allowed"
        case .denied: return "Denied"
        case .restricted: return "Restricted"
        default: return "Not asked"
        }
    }
    /// WHAT iOS HOLDS OF THIS APP'S ACCESS, IN ONE WORD (24.09). iOS ends an app whose person changes a privacy switch in
    /// Settings, and the next launch said only «reclaimed in background, cause=unexplained» (iPhone 15 13:02:40 — the
    /// photos' access changed, and the call and the screen broadcast died with the process). The run's sentinel carries
    /// this word at every breath; the next launch compares it with the present one and names the switch that moved.
    static func stamp() -> String {
        "p\(PHPhotoLibrary.authorizationStatus(for: .readWrite).rawValue)"
            + "c\(AVCaptureDevice.authorizationStatus(for: .video).rawValue)"
            + "m\(AVCaptureDevice.authorizationStatus(for: .audio).rawValue)"
            + "k\(CNContactStore.authorizationStatus(for: .contacts).rawValue)"
    }
    /// The switches that moved between two stamps, named: «photos», «camera», «microphone», «contacts».
    static func moved(from then: String, to now: String) -> [String] {
        func parts(_ s: String) -> [Character: String] {
            var out: [Character: String] = [:], key: Character? = nil
            for ch in s {
                if ch.isLetter { key = ch; out[ch] = "" } else if let k = key { out[k, default: ""].append(ch) }
            }
            return out
        }
        let a = parts(then), b = parts(now)
        let names: [(Character, String)] = [("p", "photos"), ("c", "camera"), ("m", "microphone"), ("k", "contacts")]
        return names.compactMap { a[$0.0] != nil && a[$0.0] != b[$0.0] ? $0.1 : nil }
    }
    static func tapPhotos(_ done: @escaping () -> Void) {
        MontanaTrace.mark("privacy_access", "photos tap word=\(photosWord)")
        guard PHPhotoLibrary.authorizationStatus(for: .readWrite) == .notDetermined else { MontanaSystemSettings.open(); return }
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { _ in DispatchQueue.main.async(execute: done) }
    }
    static func tapContacts(_ done: @escaping () -> Void) {
        MontanaTrace.mark("privacy_access", "contacts tap word=\(contactsWord)")
        guard CNContactStore.authorizationStatus(for: .contacts) == .notDetermined else { MontanaSystemSettings.open(); return }
        CNContactStore().requestAccess(for: .contacts) { _, _ in DispatchQueue.main.async(execute: done) }
    }
}

struct PrivacyView: View {
    /// The device forgets the person. Nothing is asked of anyone: this person exists nowhere
    /// else, and the forgetting is wholly local — content, identity and seed leave as one.
    /// The settings sheet lowers with it: the first-run page stands under it otherwise.
    private func forgetSeed() {
        // THE IDENTITY LEAVES THE NODES TOO (App Review 5.1.1(v), 08.10.2026: deleting an account deletes its records): the row of
        // the Montana top -- the name and the coins shown -- is withdrawn from every node while the words still derive its token.
        MTTopNet.shared.withdraw()
        Task { @MainActor in
            // THE NAME LEAVES FIRST (App Review 5.1.1(v), 08.10.2026: the text says so, and so it is): the keeper of names releases
            // it while the words still stand. No number is kept off this phone (10.10.2026), so none is asked back.
            await MontanaNamePlane.releaseHeld()
            // Everything the seed can reopen is sealed and on disk FIRST (15.10.4); the wipe follows.
            guard let store = ChatStore.live else { SeedScope.forget(); ui.settingsShown = false; return }
            store.sealForForget { SeedScope.forget(); ui.settingsShown = false }
        }
    }
    @AppStorage("readReceiptsEnabled") private var readReceipts = true
    @AppStorage("objectionableFilterOn") private var objectionableFilter = true   // Guideline 1.2: the fold over objectionable words
    @AppStorage("syncContactsToPhone") private var syncContacts = true
    @AppStorage(MontanaDiagConsent.key) private var diagShare = MontanaDiagConsent.birth   // the diary leaves only by this yes (08.10)
    @AppStorage(MTLinkPreviewBuilder.switchKey) private var linkPreviews = true   // the card of a link I send — my device reads that page
    @State private var presenceShared = MontanaPresencePrivacy.sharing
    @AppStorage(MTCoinShow.key) private var coinsShown = true   // the owner shows or hides their coins (04.10)
    @State private var localNetwork = MontanaPhoneNode.meshDiscoverable   // the one mesh switch owns the concept
    @ObservedObject private var place = MTLocationAccess.shared   // the one owner of the location permission says the word
    @State private var photosAccess = MTSystemAccess.photosWord       // the system's own word for this app's photos
    @State private var contactsAccess = MTSystemAccess.contactsWord   // and for its contacts
    // One decision, not two. Leaving and deleting were the same act under two names: both erase
    // the seed, and without the seed there is nothing left to come back to. Two buttons for one
    // act taught the person that one of them was reversible. The button stands here, on the
    // Privacy page, next to the seed phrase it erases (the author's word 18.09).
    @State private var confirmForget = false
    @State private var showSeed = false
    @Environment(UIState.self) private var ui

    /// A row in the phone-settings style: an icon in a coloured square, a name, the value on the right.
    private func icon(_ name: String, _ color: Color) -> some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(color)
            .frame(width: 29, height: 29)
            .overlay(Image(systemName: name).font(.system(size: 15, weight: .medium)).foregroundColor(.white))
    }

    var body: some View {
        List {
            // The permission lives with the system, and the app does not flip it: iOS has no
            // call that would change local-network access. The row leads to where it changes
            // and shows what we can see: whether announcing ourselves on the network worked.
            // It refreshes on the return-to-app event — the person came back from Settings, so
            // it is time to read anew. No polling, no timer: both would count blind between events.
            Section {
                Button { MontanaSystemSettings.open() } label: {
                    HStack(spacing: 12) {
                        icon("globe", .blue)
                        Text("Local Network").foregroundColor(.primary)
                        Spacer()
                        Text(localNetwork ? "Connected" : "Disconnected").foregroundColor(.gray)
                        Image(systemName: "chevron.right").foregroundColor(Color(white: 0.35)).font(.footnote.weight(.semibold))
                    }
                    .contentShape(Rectangle())   // the whole row is the target, not only its words (22.09)
                }
                // WHERE THIS PHONE IS, ASKED AND CHANGED HERE TOO (the author's word 23.09). The
                // permission a person never answered is asked by this very row; one already
                // decided is changed where the system keeps it — the same tap the place page
                // presses (MTLocationAccess.tap), so the two rows can never disagree.
                Button { place.tap() } label: {
                    HStack(spacing: 12) {
                        icon("location.fill", .blue)
                        Text("Location").foregroundColor(.primary)
                        Spacer()
                        Text(LocalizedStringKey(place.word)).foregroundColor(.gray)
                        Image(systemName: "chevron.right").foregroundColor(Color(white: 0.35)).font(.footnote.weight(.semibold))
                    }
                    .contentShape(Rectangle())   // the whole row is the target, not only its words (22.09)
                }
                // THE PHOTOS AND THE CONTACTS, AS iOS KEEPS THEM (the author's word 24.09): the system's own word
                // for this app and its road -- asked here if never asked, changed where the system keeps it.
                Button { MTSystemAccess.tapPhotos { refreshAccess() } } label: {
                    HStack(spacing: 12) {
                        icon("photo.fill", .blue)
                        Text("Photos").foregroundColor(.primary)
                        Spacer()
                        Text(LocalizedStringKey(photosAccess)).foregroundColor(.gray)
                        Image(systemName: "chevron.right").foregroundColor(Color(white: 0.35)).font(.footnote.weight(.semibold))
                    }
                    .contentShape(Rectangle())   // the whole row is the target, not only its words (22.09)
                }
                Button { MTSystemAccess.tapContacts { refreshAccess() } } label: {
                    HStack(spacing: 12) {
                        icon("person.crop.circle.fill", .gray)
                        Text("Contacts").foregroundColor(.primary)
                        Spacer()
                        Text(LocalizedStringKey(contactsAccess)).foregroundColor(.gray)
                        Image(systemName: "chevron.right").foregroundColor(Color(white: 0.35)).font(.footnote.weight(.semibold))
                    }
                    .contentShape(Rectangle())   // the whole row is the target, not only its words (22.09)
                }
            }
            .listRowBackground(MTGlassRowPlate())

            Section {
                // A SETTING SAYS WHAT IT DOES (the author's word 25.09: «the settings must match the behaviour»): the switch governs
                // the presence words alone; the wall, the pages, the faces and the names are carried and asked for regardless
                // (MTBoard.ask no longer reads it). The line under it is the contract, in the person's language (SETTINGS.md).
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 12) {
                        icon("eye.fill", .teal)
                        Toggle("Online status", isOn: $presenceShared)
                    }
                    Text("Only whether others see you online. Walls and pages come and go regardless.")
                        .font(.caption).foregroundColor(.gray)
                }
                // THE OWNER SHOWS OR HIDES THEIR COINS (the author's words 04.10.2026 02:47 and 02:48 UTC: «whether the balance is
                // shown each decides, on by default; who does not show is not in the top -- the privacy settings»; «the owner governs
                // privacy»): one switch for the Montana top, the coins told to correspondents and the coin's badge (MTCoinShow).
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 12) {
                        icon("trophy.fill", .orange)
                        Toggle("Show my coins", isOn: $coinsShown)
                    }
                    Text("Your name and coins stand in the Montana top for everyone, and your correspondents see your coins. Off, you are not in the top.")
                        .font(.caption).foregroundColor(.gray)
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 12) {
                        icon("checkmark.circle.fill", .green)
                        Toggle("Read receipts", isOn: $readReceipts)
                    }
                    Text("People see that you have read their messages, and channel owners count your views. Off, nobody is told.")
                        .font(.caption).foregroundColor(.gray)
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 12) {
                        icon("person.crop.circle.fill", .orange)
                        Toggle("Sync contacts", isOn: $syncContacts)
                    }
                    Text("A contact you save in Montana with a public name gets a card in the phone's Contacts. Off, no card is written.")
                        .font(.caption).foregroundColor(.gray)
                }
                // THE CARD OF A LINK IS READ BY MY OWN DEVICE (the author's word 22.09): sending a link
                // with the switch on, this phone opens that page to take its title and picture, and the
                // site sees this phone's address. Off, nothing is read and the letter carries the bare
                // link. The person I write to never opens anything either way.
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 12) {
                        icon("link", .blue)
                        Toggle("Link previews", isOn: $linkPreviews)
                    }
                    Text("Your phone reads the page of a link you send, so that site sees this phone.")
                        .font(.caption).foregroundColor(.gray)
                }
                // THE DIARY LEAVES ONLY BY THE PERSON'S YES (App Review 5.1.1(ii), 08.10.2026): off, nothing of the diary leaves this
                // phone -- the app's own nor its extensions' (MontanaDiagConsent).
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 12) {
                        icon("stethoscope", .gray)
                        Toggle("Share diagnostics", isOn: $diagShare)
                    }
                    Text("Event records with no message content, names or addresses go to Montana's nodes to help fix defects and are kept for seven days. Off, nothing leaves this phone.")
                        .font(.caption).foregroundColor(.gray)
                }
            }
            .listRowBackground(MTGlassRowPlate())
            // THE WALL (the author's word 24.09): who may write on my wall, and who may see it — everyone, until the
            // person says otherwise.
            Section {
                NavigationLink { MTBoardRulePage(act: .write) } label: {
                    HStack(spacing: 12) {
                        icon("text.below.photo", .blue)
                        Text("Who can write on my wall").foregroundColor(.primary)
                    }
                }
                NavigationLink { MTBoardRulePage(act: .see) } label: {
                    HStack(spacing: 12) {
                        icon("eye", .blue)
                        Text("Who can see my wall").foregroundColor(.primary)
                    }
                }
            } footer: {
                // THE RULE'S CONTRACT (the author's word 25.09): what «Everyone» reaches, and when a wall arrives (MTBoard.look).
                Text("Everyone means every person you have a conversation with. A wall reaches a person's page the moment they open it.")
                    .font(.caption).foregroundColor(.gray)
            }
            .listRowBackground(MTGlassRowPlate())
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 12) {
                        icon("eye.slash.fill", .purple)
                        Toggle("Filter objectionable content", isOn: $objectionableFilter)
                            .onChange(of: objectionableFilter) { _, on in MontanaKeychain.set("objectionableFilterOn", Data([on ? 1 : 0])) }
                    }
                    Text("Messages, wall posts and comments from others with offensive words stay folded until you tap them.")
                        .font(.caption).foregroundColor(.gray)
                }
                NavigationLink { MontanaBlockedView() } label: {
                    HStack(spacing: 12) {
                        icon("hand.raised.fill", .red)
                        Text("Blocked users").foregroundColor(.primary)
                    }
                }
            }
            .listRowBackground(MTGlassRowPlate())

            Section {
                NavigationLink { SeedShowView().montanaMotionMeter() } label: {
                    HStack(spacing: 12) {
                        icon("key.horizontal.fill", .gray)
                        Text("Seed phrase").foregroundColor(.primary)
                    }
                }
            }
            .listRowBackground(MTGlassRowPlate())

            Section {
                Button(role: .destructive) { confirmForget = true } label: {
                    Text("Delete account").foregroundColor(.red)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .listRowBackground(MTGlassRowPlate())
        }
        .alert("Delete account?", isPresented: $confirmForget) {
            // The words come first: a person who has no phrase must leave here toward it,
            // not past the edge from which there is no return.
            Button("Show seed phrase") { showSeed = true }
            Button("Delete account", role: .destructive) { forgetSeed() }
            Button("Cancel", role: .cancel) {}
        } message: {
            let rest = Text("Your account is deleted: this device erases your 24-word identity, and your public name leaves Montana's nodes. Your history stays here sealed and opens again only from the same 24 words — on this device, or on another one that already holds a copy. Nobody keeps the words for you: write them down first: Settings → Privacy → Seed phrase. Deleting the app erases the history as well.")
            // THE COINS ARE SAID BEFORE THE WORDS GO (the author's word 12.10.2026 12:3x UTC, No.66, after 4 105 470 coins stood on a
            // forgotten account on 11.10): an account that holds coins says how many, and that only its 24 words bring them back.
            let coins = MTCoinSplit.shared.available
            if 0 < coins {
                // USER-DATA: two line breaks between the coins' line and the rest
                Text("This account holds \(MTCoinText.count(coins)) coins. They stay with its 24 words and come back only with them.") + Text(verbatim: "\n\n") + rest
            } else {
                rest
            }
        }
        .sheet(isPresented: $showSeed) {
            NavigationStack { SeedShowView() }.preferredColorScheme(.dark).montanaMotionMeter()
        }
        .foregroundColor(.primary)
        .scrollContentBackground(.hidden)
        .montanaPageGround()   // my page's ground, as the drawer and my page wear it (25.09)
        .navigationTitle("Privacy")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: presenceShared) { _, v in MontanaPresencePrivacy.setSharing(v) }   // 10-C.3
        .onChange(of: coinsShown) { _, v in MTTopNet.shared.showChanged(v) }   // the table and the pairs hear it now
        .onChange(of: diagShare) { _, _ in MontanaDiagConsent.apply() }   // off: the extensions lose the diary's id at once
        .onAppear { refreshAccess() }
        // Returning to the app is that very event: the person may have changed the permission
        // in Settings, and the reading belongs here, not on a loop.
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            refreshAccess()
        }
    }

    private func refreshAccess() {
        localNetwork = MontanaBonjour.shared.announceAccepted
        place.refresh()
        photosAccess = MTSystemAccess.photosWord
        contactsAccess = MTSystemAccess.contactsWord
    }
}

// ════════════════════════════════════════════════════════════
// IDENTITY — birth out of twenty-four words, or opening an existing one with them
// ════════════════════════════════════════════════════════════
// What the seed opens beyond its words: the twin, the signing keys, the door a seed enters by.
// The seed itself lives in E2ECore.swift (shared with the extension); this is the app's side of it.
extension MontanaSeed {

    /// The correspondence a person has with their own other devices. They share one seed, therefore
    /// one owner branch of it, therefore one secret — so the twin is a correspondence like any
    /// other, and it needs no name of a person to be reached by. Nothing here is public.
    ///
    /// **Derived once and kept, rather than recomputed on every launch.** The path to it runs
    /// through the stretch the phrase is protected by — a million iterations, and on a phone that
    /// is 1.85 seconds, measured by the marks around the store this value is first asked for.
    /// Those seconds bought nothing: a stretch exists to cost a guesser dearly for every phrase
    /// they try, and at launch there is nothing to guess — the phrase is already on the device,
    /// sealed under the key of the device, and whoever opened that store holds the phrase itself.
    /// So the work was pure recomputation over an input already in hand, and it was paid in front
    /// of a person opening their app.
    ///
    /// What is kept is the reference and never the secret: the secret already lives in the sealed
    /// book of pipes, put there by `establish` the first time, and the reference is a filing name
    /// derived from it. Its store is sealed by the same device key that seals the phrase, so it is
    /// less sensitive than what already lies beside it and adds no surface of its own. A kept
    /// reference whose secret the book does not hold is refused and derived afresh — that way a
    /// cleared book heals itself instead of sending letters nobody can answer.
    private static let twinKey = "mt.twin.ref"

    static var twin: String? {
        if let d = MontanaLocalVault.getDecrypted(twinKey),
           let ref = String(data: d, encoding: .utf8), !ref.isEmpty,
           MTPipeBook.holds(ref) { return ref }
        guard let m = MontanaSeed.mnemonic,
              let master = MontanaQueueKeys.masterSeed(m),
              let owner = MTPipe.ownerSecret(masterSeed: master),
              let ref = MTPipeBook.establish(secret: owner, seal: false) else { return nil }
        MontanaLocalVault.setEncrypted(twinKey, Data(ref.utf8))
        return ref
    }

    /// The seed left, so the reference derived from it leaves too. It stands at the boundary that
    /// changes the seed and nowhere else: were it beside the callers, the next caller would inherit
    /// the previous identity's twin in silence — and answer for a correspondence that is not theirs.
    static func forgetTwin() { MontanaLocalVault.setEncrypted(twinKey, Data()) }

    /// The signing keys of this person, derived once and kept.
    ///
    /// **The phrase is never handed to anything at runtime, and that is the whole point.** Caching
    /// the master seed on the Swift side does nothing for a call that takes the *phrase*: the core
    /// re-runs the stretch inside itself, a million iterations again, and no cache on this side can
    /// see it. That is what put a second stretch into the start of the radio — measured at the
    /// marks around it — while a cache stood right beside it doing nothing.
    ///
    /// So the rule is one node, not one cache: whatever the phrase produces is produced once, at
    /// the moment a person is born or restored, and everything afterwards reads the result. The
    /// result is sealed by the device key that already seals the phrase, so it is no more exposed
    /// than what lies beside it, and a stretch protects a phrase against guessing — a thing that
    /// does not happen while the app is running with the phrase already in its own store.
    private static let keysKey = "mt.account.keys"
    private static let pubLen = 1952, skLen = 4032

    static func keys() -> (pub: Data, sk: Data)? {
        if let d = MontanaLocalVault.getDecrypted(keysKey), d.count == pubLen + skLen {
            return (d.prefix(pubLen), d.suffix(skLen))
        }
        guard let m = MontanaSeed.mnemonic, let acc = MontanaSeedKeys.keys(from: m),
              acc.pubkey.count == pubLen, acc.seckey.count == skLen else { return nil }
        var blob = acc.pubkey; blob.append(acc.seckey)
        MontanaLocalVault.setEncrypted(keysKey, blob)
        return (acc.pubkey, acc.seckey)
    }

    static func forgetKeys() { MontanaLocalVault.setEncrypted(keysKey, Data()) }


    @discardableResult
    static func open(_ acc: MontanaSeedKeys.Keys) -> Bool {
        // SINGLE seed record: device-local Keychain (Secure Enclave) + encrypted file backup; all other
        // seed stores (including iCloud-synced, sovereign*) are wiped. Everything else is derived from the seed on the fly.
        // Without the seed in storage there is no identity: everything else is derived, and at the
        // next launch there would be nothing to derive it from.
        guard MontanaSeed.setActive(mnemonic: acc.mnemonic) else { return false }
        // The tag of this device is derived from the seed, so the boundary that changes the seed
        // is the boundary that drops the tag. Placed here and not beside each caller: were it
        // beside the callers, a third caller would inherit the previous identity's tag in silence.
        E2E.forgetDeviceTag()
        forgetTwin(); forgetKeys()   // the same and for the same reason: derived from the departed seed
        // Nothing about the person is written down: there is no identifier of one to write.
        // What this device answers for is the correspondence with its own twin, and that is
        // derived from the seed at the moment it is needed.
        _ = twin
        MontanaTrace.mark("seed_applied", "derived_dropped=1")
        NotificationCenter.default.post(name: .montanaSeedOpened, object: nil)
        return true
    }

    /// THE ONE DOOR INTO A PERSON (the critic, 28.09): the seed opens and the boundary between two people is crossed in
    /// the same act -- the twin correspondence is derived from the seed, and it changes when, and only when, the person
    /// does. Two roads enter here: a birth and the 24 words. The words' road once opened the seed and
    /// left the boundary where the previous person had left it.
    @discardableResult
    static func enter(_ acc: MontanaSeedKeys.Keys) -> Bool {
        // THE SEATS (the second identity checklist, 1.4): the words of a person waiting on this phone's shelf lift that
        // person's seat, and no second copy of them is born; a person born or opened beside others takes a seat of their own.
        if MTSeats.lift(words: acc.mnemonic) { return true }
        // The door never writes a person over another (the author's word 30.09): beside a person seated, every road parks
        // them first (MTSeats.makeRoom). A call that reaches here with another person seated is refused, and says so.
        if let held = MontanaSeed.mnemonic, held != acc.mnemonic {
            MontanaTrace.mark("seed_enter", "REFUSED another person is seated")
            return false
        }
        guard open(acc) else { return false }
        if let b = twin { SeedScope.change(to: b) }
        MTSeats.born()
        return true
    }
}

struct MontanaOnboardingView: View {
    var onDone: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var step = 0
    @State private var montanaRoad = false                // the doors screen chose Montana: the two roads to a seed stand behind it (29.09)
    @State private var terms = false                      // the terms, opened from the doors' footer
    @State private var ground = false                     // the person's ground, chosen before the person is made (the author's word 30.09)
    @State private var bornKeys: MontanaSeedKeys.Keys?
    @State private var understood = false
    @State private var savedWords = false
    @State private var recoverInput = ""
    @State private var recoverError = ""
    @State private var recovering = false
    @State private var creating = false
    @State private var birthFailed = false
    @State private var copied = false
    @State private var glow = false   // golden radial glow of the logo (Montana style)
    @State private var refusal: LocalizedStringKey? = nil // the word of a refusal on the way back, spoken, never walked past (28.09)
    @State private var retry: (() -> Void)? = nil         // what «Try again» does
    @State private var nodeHost = ""                      // the person's own node, named beside the words
    @State private var takingWord: LocalizedStringKey = "Opening your identity…"
    @ObservedObject private var homeNode = HomeNodeWatch.shared   // the node's copy on its way back, for the bar
    @ObservedObject private var keep = MTKeeping.shared           // the parts coming back from the people one wrote to (08.10)
    @State private var barSince = Date()                          // when the bar first stood on the page: the time left is measured from it
    @ObservedObject private var seats = MTSeats.shared            // a person being added: the page stands on the Montana road (06.10)
    @ObservedObject private var grounds = MTWallpaper.Book.shared // birthChosen: the new person chose a ground, the pages wear it from then on

    var body: some View {
        ZStack {
            // THE LOGIN PAGE IS BURGUNDY BY DEFAULT (the author's word 06.10.2026 12:1x UTC: «by default the login page has the burgundy
            // ground»): the author's file as it came, until the person being made chooses a ground of their own (ground).
            if grounds.birthChosen {
                Color.clear.montanaPageGround().allowsHitTesting(false)   // the login pages wear the one ground of every page
            } else {
                MTWallpaper.paint(MTWallpaper.burgundy).ignoresSafeArea().allowsHitTesting(false)
            }
            if step == 3 {
                // Same profile screen as in settings — one source, no second implementation
                ProfileView(onboarding: true, onFinish: { onDone() })
            } else {
                VStack { Group {
                    switch step {
                    // THE PAGE DOES NOT OPEN TWICE (the author's word 06.10.2026 12:1x UTC: «from the side panel the login page reloads, and
                    // after the tap opens again»): a person being added (MTSeats.adding) already chose Montana at the door; the first screen
                    // that stands after the seat is emptied opens on the Montana road, whichever page took the road's one-time word.
                    case 0: if montanaRoad || seats.adding { intro } else { doors }   // the doors first (the author's design 29.09), the Montana road behind
                    case 1: responsibility
                    case 2: seed
                    case 4: recover
                    case 5: takingBack
                    default: EmptyView()
                    }
                } }.padding(24)
                .padding(.top, back == nil ? 0 : 28)
                .overlay(alignment: .topLeading) {
                    if let act = back {
                        MontanaCallMark(glyph: "chevron.backward", label: "Back", action: act)
                            .padding(.leading, 12).padding(.top, 4)
                    }
                }
            }
        }
        .environment(\.colorScheme, MTWallpaper.birthScheme)   // the words wear the ink of the ground the page stands on
        .interactiveDismissDisabled()
        // A making that ends leaves the next one on the login page's own ground; the ground's cover, which hides this screen for
        // a moment, comes back after its checkmark has set the choice.
        .onDisappear { if MontanaSeed.hasSeed { grounds.birthChosen = false } }
        .onAppear {   // opened to make a second person: the Montana road beside the seated one
            if MTSeats.shared.takeMontanaRoad() { montanaRoad = true }
        }
        // THE GROUND COMES BEFORE THE PERSON (the author's word 30.09: «before the identity is made it shows the page choosing the
        // identity's ground, then that ground on every page of the making, up to the chats»): the very page of my page's ground,
        // over everything -- the root's way back stands over this screen -- and its checkmark makes the person.
        .fullScreenCover(isPresented: $ground) {
            MTWallpaperPicker(task: .page, onDone: { grounds.birthChosen = true; createSeed() }).environment(\.montanaClose, nil)
        }
        .alert("The identity could not be stored on this device", isPresented: $birthFailed) {
            Button("Got it", role: .cancel) {}
        } message: {
            Text("Nothing was created. Unlock the device and try again — an identity that is not stored cannot be opened at the next launch.")
        }
        // EVERY REFUSAL ON THE WAY BACK IS SPOKEN (the critic, 28.09): the first screen once walked into an empty app
        // without a word when the node held nothing, iCloud was off or the copy did not come.
        .alert("Your history", isPresented: Binding(get: { refusal != nil }, set: { v in if !v { refusal = nil } })) {
            Button("Try again") { let again = retry; refusal = nil; again?() }
            Button("Continue without the copy") { refusal = nil; retry = nil; onDone() }
        } message: {
            if let w = refusal { Text(w) }
        }
    }

    /// THE ONE WAY BACK OF THE PATH (the author's word 29.09, 23:25: the buttons in the new style of our OS, and so every page
    /// up to the chats): the platform's back chevron on its glass circle, top left where the system draws its own -- one mark
    /// (MontanaCallMark) for every page of the path, never a grey word at the foot of each. The doors are the start, the copy
    /// coming back and the name lead only forward.
    private var back: (() -> Void)? {
        switch step {
        case 0:
            if montanaRoad { return { montanaRoad = false } }
            if seats.adding, !MontanaSeed.hasSeed { return { MTSeats.shared.returnToLast() } }   // the person on the shelf comes back
            return nil
        case 1: return { step = 0 }
        case 2: return { step = 1 }
        case 4: return { step = 0; recoverError = "" }
        default: return nil
        }
    }

    /// A person is born as an identity by their own act, and by no other event.
    ///
    /// This used to happen when the screen merely appeared: opening the app drew a seed, wrote it
    /// to the keychain and made it active, so someone who only looked at the first screen already
    /// held an identity they had not asked for. The act is the tap on «Create», and the boundary
    /// that leaves the previous identity is crossed here — before the person enters anything for
    /// the new one, so their own profile is never taken for the previous identity's content.
    func createSeed() {
        guard bornKeys == nil, !creating else { step = 1; return }
        creating = true
        Task.detached {
            let t0 = Date()
            let acc = MontanaSeedKeys.generate()
            let ms = Int(Date().timeIntervalSince(t0) * 1000)
            await MainActor.run {
                creating = false
                guard let acc else { birthFailed = true; return }
                // The seed must land in storage: without it there is no identity, and the next
                // launch has nothing to derive it from. This boundary's answer used to be
                // discarded — the person walked on as born, then hit a screen that would not close.
                guard MontanaSeed.enter(acc) else {   // the seed and the boundary between two people, in one act
                    MontanaTrace.mark("seed_born", "ms=\(ms) stored=0")
                    birthFailed = true
                    return
                }
                bornKeys = acc
                MontanaTrace.mark("seed_born", "ms=\(ms) stored=1")
                MontanaEntropy.report("birth")   // what this identity stands on — recorded that same instant
                step = 1
            }
        }
    }

    var intro: some View {
        VStack(spacing: 18) {
            Spacer()
            ZStack {
                // soft radial golden glow-halo (Montana style)
                RadialGradient(colors: [Color.accentColor.opacity(glow ? 0.55 : 0.28), Color.accentColor.opacity(0.0)],
                               center: .center, startRadius: 2, endRadius: glow ? 155 : 115)
                    .frame(width: 300, height: 300)
                    .blur(radius: 34)
                    .scaleEffect(glow ? 1.08 : 0.92)
                    .allowsHitTesting(false)
                Image("Logo").resizable().scaledToFit().frame(width: 66, height: 66)
                    .shadow(color: Color.accentColor.opacity(glow ? 0.85 : 0.4), radius: glow ? 20 : 8)
            }
            .frame(height: 120)
            .onAppear { withAnimation(.easeInOut(duration: 2.3).repeatForever(autoreverses: true)) { glow = true } }
            Text("Montana").font(.system(size: 40, weight: .bold)).foregroundColor(Color.accentColor)
            Text("A private messenger. Your identity comes from your secret phrase, and your chats are encrypted on your device.")
                .font(.subheadline).foregroundColor(.gray).multilineTextAlignment(.center).padding(.horizontal, 20)
            VStack(alignment: .leading, spacing: 12) {
                privRow("key.fill", "Identity from 24 words", "Only you hold the key")
                privRow("lock.shield.fill", "End-to-end encryption", "The key lives on your devices")
                // WHAT IS TRUE OF THIS BUILD, NOT OF AN OLDER ONE (App Review 2.3.1(a), 08.10.2026): addresses are no longer
                // exchanged -- a person is reached by a name or an invitation -- and a letter the far phone cannot take at once
                // waits on a node as an envelope the node cannot open.
                privRow("at", "Name or invitation", "People reach you by either")
                privRow("point.3.connected.trianglepath.dotted", "Sealed on the way", "Nodes carry envelopes they cannot open")
            }
            Spacer()
            // EVERY ACT OF THE PATH IS A DOOR (the author's word 29.09, 23:25: the buttons in the new style of our OS): the one plate of the doors
            // (MTLoginDoorStyle), the main act on the platform's blue glass, the second on its clear glass; gold is the sign's alone.
            Button { guarded(own: true) { if bornKeys == nil { ground = true } else { createSeed() } } } label: {
                HStack(spacing: 8) {
                    if creating { ProgressView().tint(.white) }
                    Text(creating ? "Bringing an identity into being…" : "Create")
                }
            }
            .buttonStyle(MTLoginDoorStyle(tint: MontanaOctagon.platformBlue)).disabled(creating)
            Button { guarded { step = 4 } } label: { Text("Open identity") }
                .buttonStyle(MTLoginDoorStyle())
            Text(MontanaVersion.footer)
                .font(.caption2).foregroundColor(Color.gray.opacity(0.7)).padding(.top, 2)
        }
    }
    /// NOBODY IS REPLACED (the author's word 30.09: «it must not offer to replace when I create a new identity; it creates a
    /// new one and leaves the old one untouched; multiple identities with switching»). A road to a seed runs at once on an
    /// empty seat. Beside a person already seated, that person goes to the shelf first (MTSeats.makeRoom: parked, never
    /// wiped) and the first screen opens again on this road; only «Create» continues the person this very screen has just
    /// made, to their words.
    private func guarded(own: Bool = false, _ act: @escaping () -> Void) {
        guard MontanaSeed.hasSeed else { act(); return }
        if own, let b = bornKeys, MontanaSeed.mnemonic == b.mnemonic { act(); return }
        MTSeats.shared.makeRoom()
    }

    var recover: some View {
        VStack(spacing: 16) {
            Spacer().frame(height: 6)
            Image(systemName: "arrow.clockwise.circle.fill").font(.system(size: 46)).foregroundColor(Color.accentColor)
            Text("Recovery from phrase").font(.title3.bold()).foregroundColor(.primary)
            Text("Enter the 24 words separated by spaces, in the correct order.").font(.caption).foregroundColor(.gray).multilineTextAlignment(.center)
            TextEditor(text: $recoverInput).frame(height: 130).padding(8).scrollContentBackground(.hidden)
                .background(MTGlassCardPlate(cornerRadius: 14))
                .foregroundColor(.primary).autocorrectionDisabled().textInputAutocapitalization(.never)
            // THE PERSON'S OWN NODE, named beside the words (28.09): the copy it holds comes back before the first screen.
            TextField("Your node (optional)", text: $nodeHost)
                .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                .padding(12).background(MTGlassCardPlate(cornerRadius: 14)).foregroundColor(.primary)
            if !recoverError.isEmpty { Text(LocalizedStringKey(recoverError)).foregroundColor(.red).font(.caption).multilineTextAlignment(.center) }
            Button {
                let words = recoverInput.lowercased().split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "," }).map(String.init)
                if words.count != 24 { recoverError = "Exactly 24 words required (entered \(words.count))"; return }
                recoverError = ""; recovering = true
                let phrase = words.joined(separator: " ")
                Task.detached {
                    let t0 = Date()
                    let acc = MontanaSeedKeys.keys(from: phrase)
                    let ms = Int(Date().timeIntervalSince(t0) * 1000)
                    await MainActor.run {
                        recovering = false
                        if let acc = acc {
                            guard MontanaSeed.enter(acc) else {   // the seed and the boundary between two people, in one act
                                MontanaTrace.mark("seed_opened", "ms=\(ms) stored=0")
                                recoverError = "The identity could not be stored on this device"
                                return
                            }
                            MontanaTrace.mark("seed_opened", "ms=\(ms)")
                            takeFromNode()
                        } else {
                            MontanaTrace.mark("seed_refused", "ms=\(ms)")
                            recoverError = "Invalid phrase. Check the words and their order."
                        }
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    if recovering { ProgressView().tint(.white) }
                    Text(recovering ? "Restoring…" : "Restore")
                }
            }
            .buttonStyle(MTLoginDoorStyle(tint: MontanaOctagon.platformBlue)).disabled(recovering)
            Spacer()
        }
    }

    var responsibility: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "exclamationmark.shield.fill").font(.system(size: 52)).foregroundColor(.orange)
            Text("Full control — full responsibility").font(.title3.bold()).foregroundColor(.primary).multilineTextAlignment(.center)
            Text("The key to your identity is your 24-word seed phrase, which you're about to see. Recovery is only possible with it.\n\nLose it and you lose access to your identity and chats forever. Don't show it to anyone.\n\nStore it securely — using whatever method of storing confidential data you trust (for example, a password manager), or write it down by hand on paper and keep it offline. Don't take a screenshot or save it in Notes.")
                .foregroundColor(.gray).font(.subheadline)
            Toggle(isOn: $understood) { Text("I understand and take responsibility").foregroundColor(.primary).font(.subheadline) }
            Spacer()
            Button { if understood { step = 2 } } label: { Text("Show Words") }
                .buttonStyle(MTLoginDoorStyle(tint: MontanaOctagon.platformBlue)).disabled(!understood)
        }
    }

    var seed: some View {
        VStack(spacing: 14) {
            Text("Your 24-word seed phrase").font(.title3.bold()).foregroundColor(.primary)
            Text("Store it securely: a password manager you trust, or write it down on paper and keep it offline. Don't take a screenshot or store it in Notes.").font(.caption).foregroundColor(.gray).multilineTextAlignment(.center)
            if let acc = bornKeys {
                let words = acc.mnemonic.split(separator: " ").map(String.init)
                let half = (words.count + 1) / 2
                let order = (0..<half).flatMap { r -> [Int] in (r + half < words.count) ? [r, r + half] : [r] }
                ScrollView {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach(order, id: \.self) { i in
                            HStack(spacing: 6) {
                                Text("\(i + 1).").foregroundColor(.gray).frame(width: 26, alignment: .trailing)
                                Text(words[i]).foregroundColor(.primary).bold(); Spacer()
                            }.padding(7).background(MTGlassCardPlate(cornerRadius: 10))
                        }
                    }
                }
                Button { UIPasteboard.general.string = acc.mnemonic; copied = true } label: { Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc") }
                    .buttonStyle(MTLoginDoorStyle())
                Toggle(isOn: $savedWords) { Text("I've saved the words in a safe place").foregroundColor(.primary).font(.subheadline) }
                Button {
                    // address page removed: the address and QR are now on the empty chats screen and in settings
                    // The identity is already active from the moment of its creation (see
                    // onAppear): the words screen only shows them and finishes the first launch.
                    if savedWords, bornKeys != nil { step = 3 }   // the words are saved — now the name
                } label: { Text("Your identity in Montana") }
                    .buttonStyle(MTLoginDoorStyle(tint: MontanaOctagon.platformBlue)).disabled(!savedWords || bornKeys == nil)
            } else {
                Spacer(); ProgressView(); Text("Bringing an identity into being…").foregroundColor(.gray).font(.caption); Spacer()
            }
        }
    }

    // Step 12: the address page is gone. First launch ends at the words: the address is shown
    // to the person nowhere, and introductions go by @name or a one-time card.


    /// THE WORDS OPENED; THE PERSON'S OWN NODE, IF NAMED, HANDS THE COPY BACK (28.09) -- otherwise the first screen.
    /// A refusal is spoken (the critic, 28.09), with «Try again» and the person's own way on without the copy.
    func takeFromNode() {
        let h = nodeHost.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !h.isEmpty else { return takeFromKeepers() }
        MontanaHomeNode.setHost(h)
        MontanaHomeNode.setOn(true)
        takingWord = "Taking your history back"
        step = 5
        HomeNodeWatch.shared.takeBack { r in
            switch r {
            case .success(let t):
                MontanaTrace.mark("home_node", "onboarding took chats=" + String(t.chats))
                onDone()
            case .failure(let e):
                MontanaTrace.mark("home_node", "onboarding take refused " + String(describing: e))
                refuse(e.spoken(by: .node)) { takeFromNode() }
            }
        }
    }
    /// EVERY REFUSAL IS SPOKEN (the critic, 28.09): the word stands in an alert with «Try again» and «Continue without the copy».
    func refuse(_ word: LocalizedStringKey, again: @escaping () -> Void) {
        retry = again
        refusal = word
    }
    /// The person may walk on while the opening of the words (their stretch) is not under way. The copy of the people one wrote to
    /// goes on by itself behind them (the author's word 09.10.2026: «Continue -- the restore goes on in the background»): its one
    /// owner is MTKeeping, not this page; a copy from the node is this page's and is waited for.
    private var canGoOn: Bool { !creating && homeNode.restoring == nil }
    /// The copy the people one wrote to gave back, being laid: its share of frames, the engine's own count.
    private var keepLaying: Double? { if case .laying(let f) = keep.taking { return f } else { return nil } }
    /// THE ONE SHARE OF THE COPY'S ROAD (09.10.2026): the light copy coming down is the first half, its laying the second; the parts
    /// the people one wrote to hold count the first half while no light copy comes.
    private var keepShare: Double? {
        switch keep.taking {
        case .fetching(let f): return f / 2
        case .calling(let have, let need) where 0 < need: return min(1, Double(have) / Double(need)) / 2
        case .laying(let f): return 0.5 + f / 2
        default: return nil
        }
    }
    /// THE TIME LEFT, MEASURED: the time the share done so far took, stretched over the rest -- said once a twentieth is done and
    /// five seconds have passed; before that nothing is measured, and nothing is said.
    private func timeLeft(_ f: Double) -> String? {
        let spent = Date().timeIntervalSince(barSince)
        guard 0.05 <= f, f < 1, 5 <= spent else { return nil }
        let left = Int((spent * (1 - f) / f).rounded())
        return Duration.seconds(left).formatted(Duration.UnitsFormatStyle(allowedUnits: [.hours, .minutes, .seconds], width: .abbreviated,
                                                                          maximumUnitCount: 2).locale(MTLanguage.locale))
    }
    /// THE COPY KEPT BY THE PEOPLE ONE WROTE TO (MTKeeping, 08.10): with no node named, the words call the pipe of every slot; the
    /// page shows the parts in hand, and the person may walk on at any moment -- the copy is laid whenever it stands, merged.
    func takeFromKeepers() {
        takingWord = "Restoring the identity chain"   // the author's word 11.10.2026 14:13 UTC: the person's chain comes back first
        step = 5
        keep.onboardingWaits = true
        // THE LIGHT COPY LETS THE PERSON IN (App: «once the light copy is laid»): the full copy follows from the keepers.
        keep.onLight = {
            guard MTKeeping.shared.onboardingWaits else { return }
            MTKeeping.shared.onboardingWaits = false
            onDone()
        }
        keep.takeBack { r in
            guard MTKeeping.shared.onboardingWaits else { return }
            MTKeeping.shared.onboardingWaits = false
            if case .success = r { onDone() } else { refuse("No copy came back") { takeFromKeepers() } }
        }
    }
    var takingBack: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "arrow.down.circle.fill").font(.system(size: 46)).foregroundColor(Color.accentColor)
            Text(takingWord).font(.title3.bold()).foregroundColor(.primary).multilineTextAlignment(.center)
            if case .calling(let have, let need) = keep.taking, need > 0, keepLaying == nil {
                Text("Parts in hand: \(have) of \(need)").foregroundColor(.gray).font(.caption)
            }
            // THE BAR FROM THE FIRST FRAME (the author's word 09.10.2026 08:3x UTC: «the progress bar must show at once, now it spins
            // long before it comes; under it the approximate time of the restore»): nothing measured yet is a bar at zero, never a
            // spinner, and the time left is said once it can be measured.
            let f = homeNode.fetching ?? homeNode.restoring ?? keepShare ?? 0
            ProgressView(value: f).padding(.horizontal, 24)
            Text(verbatim: String(Int(f * 100)) + "%").foregroundColor(.gray).font(.caption)   // USER-DATA: a share
            if let left = timeLeft(f) {
                Text("About \(left) left").foregroundColor(.gray).font(.caption)
            }
            Spacer()
            if canGoOn {
                Button { retry = nil; keep.onboardingWaits = false; onDone() } label: {
                    if keep.isTaking { Text("Continue") } else { Text("Continue without the copy") }
                }
                .buttonStyle(MTLoginDoorStyle())
                if keep.isTaking {
                    Text("Your history keeps coming back in the background.").foregroundColor(.gray).font(.caption).multilineTextAlignment(.center)
                }
            }
        }
        .onAppear { barSince = Date() }
    }

    /// THE DOORS (the author's design 29.09, his picture in Media): the glass icon, the title, and the Montana door pressed to
    /// the foot of the screen, smaller and neater than in his picture.
    /// The doors stand on the platform's glass; the terms and the privacy policy open from the footer's own words.
    var doors: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            Image("IconGlassPreview").resizable().scaledToFit().frame(width: 120, height: 120)
            Text("Sign in to Montana").font(.title.bold()).foregroundColor(.primary).padding(.top, 22)
            Spacer(minLength: 0)
            VStack(spacing: 10) {
                // ONE LOGIN PAGE, at the first launch and when a person is added from the drawer (the author's word 29.09 evening).
                // Beside a seed already held, the Montana door parks the person and opens the road again (MTSeats).
                Button {
                    MontanaTrace.mark("first_screen", "door=montana")
                    // Beside a person already seated the seat is emptied first (the second identity checklist, 1.4): the root's
                    // first screen then stands on this road, with the way back to the person on the shelf; nobody is replaced.
                    guarded(own: true) { montanaRoad = true }
                } label: {
                    MTDoorLabel(glyph: Image("Logo").resizable().scaledToFit(), word: Text("Continue with Montana"))
                }
                .buttonStyle(MTLoginDoorStyle())
            }
            .frame(maxWidth: 420)
            Text("By continuing, you agree to the [Terms of Use](montana://terms) and [Privacy Policy](montana://privacy).")
                .font(.caption2).foregroundColor(.gray).tint(Color.white.opacity(0.8))
                .multilineTextAlignment(.center).padding(.top, 14).padding(.horizontal, 12)
        }
        .environment(\.openURL, OpenURLAction { url in
            if url.scheme == "montana", url.host == "terms" { terms = true; return .handled }
            if url.scheme == "montana", url.host == "privacy", let page = URL(string: MontanaSafety.privacy) { return .systemAction(page) }
            return .systemAction
        })
        .sheet(isPresented: $terms) { NavigationStack { MontanaTermsView() } }
    }
    func privRow(_ icon: String, _ title: String, _ sub: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundColor(Color.accentColor).frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(title)).foregroundColor(.primary).font(.subheadline.bold())
                Text(LocalizedStringKey(sub)).foregroundColor(.gray).font(.caption)
            }
            Spacer()
        }
    }
}


/// ONE DOOR'S FACE: the glyph at the left, the word in the middle, the chevron at the right; the 52-point capsule, the whole
/// of it the target, is the plate's own (MTLoginDoorStyle). The login page's Montana door and the Montana room's update wear
/// this one face (the author's word 03.10: «the button like Continue with Montana on the login page»).
struct MTDoorLabel<Glyph: View>: View {
    let glyph: Glyph
    let word: Text
    var body: some View {
        HStack(spacing: 12) {
            glyph.frame(width: 26, height: 26)
            Spacer(minLength: 0)
            word.font(.body.weight(.semibold)).foregroundColor(.primary).lineLimit(1).minimumScaleFactor(0.8)
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundColor(.secondary)
        }
    }
}

/// THE DOOR'S PLATE (29.09): a capsule of the platform's glass, tinted with the door's own colour, where the system has it;
/// the thin material with the tinted rim before, so a door reads as a door on every device. The press is the platform's own.
/// EVERY ACT OF THE PATH STANDS ON IT (the author's word 29.09, 23:25: the buttons in the new style of our OS, and so every
/// next page up to the chats): the doors and the path's acts from the first screen to the chats -- create, open, show the
/// words, copy them, restore, go on without the copy, agree to the terms -- wear this one plate,
/// never a fill of their own. A tint is a door's own colour or the page's main act (the platform's blue, the system's
/// prominent glass); none -- the platform's clear glass, a second act. The plate owns the size (52 points high, 420 wide at
/// most, the whole capsule the target), the word's face and the dimmed look of an act not yet open.
struct MTLoginDoorStyle: ButtonStyle {
    var tint: Color? = nil
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        face(configuration.label
                .font(.body.weight(.semibold)).foregroundColor(.primary).lineLimit(1).minimumScaleFactor(0.8)
                .padding(.horizontal, 18)
                .frame(maxWidth: .infinity).frame(height: 52)
                .contentShape(Capsule()))
            .frame(maxWidth: 420)
            .opacity(enabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
    @ViewBuilder private func face(_ label: some View) -> some View {
        if #available(iOS 26.0, *), MontanaSkin.isNative {
            label.background(MTGlassPlate(glass: glass, shape: Capsule()))
                .overlay(Capsule().stroke(rim.opacity(0.35), lineWidth: 1))
        } else {
            label.background(Capsule().fill(MontanaOctagon.barMaterial))
                .overlay(Capsule().stroke(rim.opacity(0.45), lineWidth: 1))
        }
    }
    @available(iOS 26.0, *)
    private var glass: Glass {
        guard let tint else { return Glass.regular.interactive() }
        return Glass.regular.tint(tint.opacity(0.28)).interactive()
    }
    /// The rim of a clear door is the platform's faint light, of a tinted one its own colour.
    private var rim: Color { tint ?? Color.white.opacity(0.6) }
}


// ════════════════════════════════════════════════════════════
// PROFILESETUPVIEW — First name, Last name, avatar
// The name is saved on the server (display_name).
// ════════════════════════════════════════════════════════════

// ════════════════════════════════════════════════════════════
// ════════════════════════════════════════════════════════════

// ════════════════════════════════════════════════════════════
// WELCOMEVIEW — splash screen: the sign lights up like a signboard
// ════════════════════════════════════════════════════════════

// ════════════════════════════════════════════════════════════
// WELCOMEVIEW — splash screen: the sign lights up like a signboard
// ════════════════════════════════════════════════════════════
struct WelcomeView: View {
    var onFinish: () -> Void
    @State private var appear = false
    @State private var glow = false

    var body: some View {
        ZStack {
            VStack(spacing: 22) {
                Image("Logo")
                    .resizable().scaledToFit()
                    .frame(width: 87, height: 87)
                    .shadow(color: Color.accentColor.opacity(glow ? 0.95 : 0.15), radius: glow ? 35 : 4)
                    .shadow(color: Color.accentColor.opacity(glow ? 0.7 : 0.0),  radius: glow ? 70 : 0)
                    .shadow(color: Color.accentColor.opacity(glow ? 0.5 : 0.0),  radius: glow ? 110 : 0)
                    .scaleEffect(appear ? 1.0 : 0.6)
                    .opacity(appear ? 1 : 0)

                Text("Montana")
                    .font(.system(size: 40, weight: .bold))
                    .foregroundColor(Color.accentColor)
                    .shadow(color: Color.accentColor.opacity(glow ? 0.9 : 0.1), radius: glow ? 18 : 2)
                    .opacity(appear ? 1 : 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .montanaPageGround()   // the ground of the terms before it and the chats after it: no black between
        .onAppear {
            withAnimation(.easeOut(duration: 0.4)) { appear = true }
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true).delay(0.15)) {
                glow = true
            }
            // the splash dismisses faster (was 2.8 s)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { onFinish() }
        }
    }
}

/// ACCESS BY LEVEL (the author's words 16.10.2026 15:2x UTC: «in the settings a path Access by level -- where they open for each»; «we
/// have the gamification of access to Montana's functions»): the person's Global Level on top, and under each level the functions it
/// opens (MTLevelAccess) -- switches the person moves once their level reaches it, each with its contract under it (SETTINGS.md).
struct MTLevelAccessPage: View {
    @ObservedObject private var person = MTPersonChain.shared
    @ObservedObject private var split = MTCoinSplit.shared   // the available, the one number of the person's coins (fold-7)
    @ObservedObject private var fabric = MTFabric.shared   // the third level the Global one is the lowest of (MTFabric, 17.10)
    @AppStorage(MTCallRecordingPolicy.key) private var recordCalls = true
    @AppStorage(MTLevelAccess.keepKey) private var keepDeleted = true
    private var level: Int { MTPersonChain.global(person: person.level, balance: split.available) }
    var body: some View {
        let seven = MTLevelAccess.Feature.keepDeleted.level
        let open = MTLevelAccess.opens(.keepDeleted)
        let recordOpen = MTLevelAccess.opens(.autoRecord)
        let eight = MTLevelAccess.Feature.ownNode.level
        let nodeOpen = MTLevelAccess.opens(.ownNode)
        List {
            Section {
                Text("Global level \(level)")
                // THE FABRIC OF TIME BESIDE THE GLOBAL LEVEL (the author's word 17.10.2026 19:50 UTC: «at once let a new level appear in
                // the clients that sets the global one, named Fabric of Time»): its level this turn, and through its first two turns
                // the days until its first count.
                LabeledContent {
                    // USER-DATA: the level of the fabric of time now, a number, or a dash before this life has read it
                    Text(verbatim: fabric.level.map { n in String(n) } ?? "—").monospacedDigit()
                } label: {
                    Label("Fabric of Time", systemImage: "point.3.connected.trianglepath.dotted")
                }
                if let days = fabric.graceDays {
                    Text("Days until the first count: \(days)").font(.caption).foregroundColor(.gray)
                }
            } footer: {
                Text("Your level is the lowest of three: your time in Montana, the coins you hold and the Fabric of Time, the people you write to and call regularly in the last two weeks, weighed by the levels their own time and wallet give them. Each level opens new functions of Montana.")
            }
            .listRowBackground(MTGlassRowPlate())
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    // BELOW ITS LEVEL A SWITCH STANDS OFF (the author's word 16.10.2026 17:34 UTC: «if the level has not reached 7, the
                    // accesses by level are off by default, these checkmarks»): the switch shows what works -- nothing until the level
                    // opens it; the person's own choice is kept for the day it does.
                    Toggle("Forbid deletion on my phone", systemImage: "lock.shield",
                           isOn: Binding(get: { open && keepDeleted }, set: { on in keepDeleted = on }))
                    Text("A message your correspondent deletes for everyone stays on this phone, and their phone is told so.")
                        .font(.caption).foregroundColor(.gray)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Record calls", systemImage: "record.circle",
                           isOn: Binding(get: { recordOpen && recordCalls }, set: { on in recordCalls = on }))
                    Text("Calls are recorded by themselves on this phone and sent to the call's chat after your first consent. While this is off, a correspondent whose level is not above yours cannot record your calls; one with a higher level records on their side only. The record button on the call screen works on every level unless the correspondent's switch holds.")
                        .font(.caption).foregroundColor(.gray)
                }
            } header: {
                Text("Level \(seven)")
            } footer: {
                if !open { Text("Opens at level \(seven). Your level is \(level).") }
            }
            .disabled(!open)
            .listRowBackground(MTGlassRowPlate())
            // LEVEL 8 (the author's word 17.10.2026 15:1x UTC: only from level 8 can one connect one's own node to the Montana
            // network through the client): the page of one's node, where it is set up and its copies go; its copy comes back on
            // every level, on that page and on the first screen.
            Section {
                NavigationLink { HomeNodeView() } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Your node", systemImage: "server.rack")
                        Text("Connect a machine you own to the Montana network through this app: it is set up from here and copies of the whole phone go to it. Taking your copy back is open on every level.")
                            .font(.caption).foregroundColor(.gray)
                    }
                }
            } header: {
                Text("Level \(eight)")
            } footer: {
                if !nodeOpen { Text("Opens at level \(eight). Your level is \(level).") }
            }
            .disabled(!nodeOpen)
            .listRowBackground(MTGlassRowPlate())
        }
        .foregroundColor(.primary)
        .scrollContentBackground(.hidden)
        .montanaPageGround()
        .navigationTitle("Access by level")
        .navigationBarTitleDisplayMode(.inline)
        .modifier(MTCallRecordingConsent())
        .onChange(of: recordCalls) { _, on in MTCallRecording.shared.changed(on) }
        .onChange(of: keepDeleted) { _, _ in MTLevelAccess.mirror() }
        .onAppear { MTLevelAccess.mirror(); fabric.prime(); fabric.refresh() }
    }
}

/// THE GREEN SHIELD (the author's word 16.10.2026 17:34 UTC: «a message cannot be deleted while the protection is on; a tap on the
/// shield shows the rule of the levels and the way to the settings»): it stands while this phone keeps what others delete
/// (MTLevelAccess.keepsDeleted); a tap lays the rule over it in the platform's own popover, whose last row is the way to Access by level.
/// A BADGE ON THE INTERLOCUTOR'S BUBBLE (the author's word 17.10.2026 15:4x UTC: «the shield moves to a badge in the top right corner
/// of the interlocutor's bubble inside the chat»): the platform's green round with the white shield, over the corner of the name's
/// capsule at the chat's top, as a count stands over a mark; its target is the platform's least.
struct MTKeepShield: View {
    @Environment(UIState.self) private var ui
    @ObservedObject private var person = MTPersonChain.shared
    @ObservedObject private var split = MTCoinSplit.shared   // the available, the one number of the person's coins (fold-7)
    @ObservedObject private var fabric = MTFabric.shared   // the Global Level the rule names follows the fabric too
    @AppStorage(MTLevelAccess.keepKey) private var keepDeleted = true
    @State private var told = false
    var body: some View {
        if MTLevelAccess.keepsDeleted {
            Button { told = true } label: {
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .background(Color(uiColor: .systemGreen), in: Circle())
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Forbid deletion on my phone"))
            .popover(isPresented: $told) { rule.presentationCompactAdaptation(.popover) }
        }
    }
    private var rule: some View {
        let seven = MTLevelAccess.Feature.keepDeleted.level
        let level = MTPersonChain.global(person: person.level, balance: split.available)
        return VStack(alignment: .leading, spacing: 10) {
            Label {
                Text("Deletion is forbidden on this phone").font(.headline)
            } icon: {
                Image(systemName: "checkmark.shield.fill").foregroundStyle(Color(uiColor: .systemGreen))
            }
            Text("A message your correspondent deletes for everyone stays on this phone, and their phone is told so.")
                .font(.subheadline).foregroundStyle(.secondary)
            Text("In Montana levels open functions: from level \(seven) a person can forbid deletion on their phone. Your level is \(level).")
                .font(.subheadline).foregroundStyle(.secondary)
            Divider()
            Button {
                told = false
                ui.overlayPage = .levels
            } label: {
                HStack {
                    Label("Access by level", systemImage: "stairs").foregroundStyle(.primary)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .frame(width: 320)
        .fixedSize(horizontal: false, vertical: true)
    }
}
