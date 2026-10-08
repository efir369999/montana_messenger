//
//  MontanaScreens.swift
//  Montana — a Montana messenger
//
//  Cut out of ContentView.swift whole, declaration by declaration (the author's word 10.09):
//  nothing here was renamed or rewritten; the file holds one screen and what only it reads.
//

import SwiftUI
import MessageUI
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



// A thin wrapper over the SSOT viewer: resolves the photo source and the fallback circle.
// ════════════════════════════════════════════════════════════
// ARCHIVEDCHATSVIEW — archived chats
// ════════════════════════════════════════════════════════════
struct ArchivedChatsView: View {
    @Binding var archived: [Chat]
    @Binding var chats: [Chat]
    @EnvironmentObject private var store: ChatStore
    @Environment(UIState.self) private var ui
    @State private var deletingChat: Chat?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                // The SAME row as the main list ([C-1]): same look, same swipes, same menu —
                // only «archive» turns into «unarchive».
                ForEach(archived) { chat in
                    SwipeChatRow(
                        leading: [
                            SwipeTile(icon: store.hasUnread(chat.name) ? "checkmark.message.fill" : "circle.fill", color: .blue) { store.toggleUnread(chat.name) },
                            SwipeTile(icon: store.pinnedChats.contains(chat.name) ? "pin.slash.fill" : "pin.fill", color: .orange) { store.togglePinChat(chat.name) }
                        ],
                        trailing: [
                            SwipeTile(icon: "tray.and.arrow.up.fill", color: .gray) { unarchive(chat) },
                            SwipeTile(icon: "trash.fill", color: .red) { deletingChat = chat },
                            SwipeTile(icon: store.mutedChats.contains(chat.name) ? "bell.fill" : "bell.slash.fill", color: .indigo) { store.toggleMuteChat(chat.name) }
                        ],
                        onOpen: { ui.openChat(chat) }
                    ) {
                        ChatRow(model: store.rowModel(chat))
                            .modifier(MTRowBubble())   // a bubble of one-tone glass, as the chats' rows (26.09)
                    }
                    .contextMenu {
                        Button { unarchive(chat) } label: {
                            Label("Unarchive", systemImage: "tray.and.arrow.up.fill")
                        }
                        Button { store.toggleMuteChat(chat.name) } label: {
                            Label("Muted", systemImage: "bell.slash")
                        }
                        Button { store.toggleUnread(chat.name) } label: {
                            if store.hasUnread(chat.name) { Label("Mark as read", systemImage: "checkmark.message") }
                            else { Label("Mark as unread", systemImage: "circle") }
                        }
                        Button(role: .destructive) { deletingChat = chat } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
        .montanaPageGround()   // my page's ground, as every page wears it (rule 30, 25.09)
        .navigationTitle("Archive")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if archived.isEmpty {
                Text("Archive is empty").foregroundColor(.gray)
            }
        }
        // The same delete sheet as the main list — one road for erasing a conversation.
        .overlay {
            if let c = deletingChat {
                MontanaDeleteChatSheet(
                    title: store.title(for: c),
                    photoURL: store.avatarFor(c), color: c.color, initial: store.initial(for: c),
                    canDeleteForBoth: MontanaConv.holds(c.convId ?? c.name),
                    coinsTravel: store.coinsTravel(c),
                    onBoth: { store.deleteChat(c, forBoth: true); deletingChat = nil },
                    onMine: { store.deleteChat(c, forBoth: false); deletingChat = nil },
                    onCancel: { deletingChat = nil })
            }
        }
    }

    /// The store's one road ([C-1]); the bindings follow the tab's reread of the vault.
    func unarchive(_ chat: Chat) { store.unarchiveChat(chat) }
}

// ════════════════════════════════════════════════════════════
// SETTINGS SECTION SCREENS
// ════════════════════════════════════════════════════════════

// Recent calls
struct RecentCallsView: View {
    @EnvironmentObject private var store: ChatStore
    private var contactsJSON: String { get { MontanaLocalVault.getString("mtContacts") ?? "" } nonmutating set { MontanaLocalVault.setString("mtContacts", newValue); MTNameBook.invalidateContacts() } }
    @State private var showNewCall = false
    private var contacts: [ContactsTabView.MTContact] {
        (try? JSONDecoder().decode([ContactsTabView.MTContact].self, from: Data(contactsJSON.utf8))) ?? []
    }
    // The one call log ([C-1]): the store's builder, the same the Calls tab reads.
    private var callRecords: [CallRecord] { store.callRecords() }
    var body: some View {
        List {
            Section {
                Button { showNewCall = true } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "phone.badge.plus").foregroundColor(Color.accentColor).frame(width: 26)
                        Text("New call").foregroundColor(.accentColor)
                    }
                }
            }
            .listRowBackground(MTGlassRowPlate())
            Section("Recent") {
                if callRecords.isEmpty {
                    Text("Your calls will appear here").font(.caption).foregroundColor(.gray)
                } else {
                    ForEach(callRecords) { r in
                        Button { MontanaCall.shared.startCall(peer: r.peer, device: "", video: r.video) } label: {
                            HStack(spacing: 10) {
                                Image(systemName: r.incoming ? "arrow.down.left" : "arrow.up.right")
                                    .font(.system(size: 12)).foregroundColor(r.missed ? .red : .green)
                                Text(MontanaAvatar.spokenName(store.displayName(for: r.peer))).foregroundColor(r.missed ? .red : .white)
                                    .lineLimit(1).truncationMode(.tail)
                                if r.video { Image(systemName: "video.fill").font(.system(size: 10)).foregroundColor(.gray) }
                                Spacer()
                                Text(r.time).font(.caption).foregroundColor(.gray)
                            }
                            .contentShape(Rectangle())   // the whole row is the target, not only its words (22.09)
                        }
                    }
                }
            }
            .listRowBackground(MTGlassRowPlate())
        }
        .scrollContentBackground(.hidden).montanaPageGround()   // my page's ground, as every page wears it (26.09)
        .navigationTitle("Calls").navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showNewCall) {
            NavigationStack {
                List(contacts) { c in
                    Button {
                        showNewCall = false
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "phone.fill").foregroundColor(.green)
                            Text(MTNameBook.display(conv: c.ref)).foregroundColor(.white)   // the book's one order; the card is inside it
                            .lineLimit(1).truncationMode(.tail)
                        }
                    }
                }
                .scrollContentBackground(.hidden).montanaPageGround()   // my page's ground, as every page wears it (26.09)
                .navigationTitle("New call").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { MontanaCloseMark { showNewCall = false } } }
            }.preferredColorScheme(.dark)
        }
    }
}

// Devices (sessions)
// ── QR device linking (Signal model): UI ──
// ── Stage 8: identity fingerprint verification (safety number) ──
/// Which correspondences this person has checked face to face. The list is device-local and holds
/// the local names of correspondences — there is no identifier of a person to hold instead.
enum SafetyStore {
    private static let key = "mtVerifiedConversations"
    private static func list() -> [String] {
        (UserDefaults.standard.array(forKey: key) as? [String]) ?? []
    }
    static func isVerified(_ conv: String) -> Bool { list().contains(conv) }
    static func setVerified(_ conv: String, _ on: Bool) {
        guard !conv.isEmpty else { return }
        var s = list(); s.removeAll { $0 == conv }
        if on { s.append(conv) }
        UserDefaults.standard.set(s, forKey: key)
    }
}

struct SafetyNumberView: View {
    let peerRef: String
    let peerName: String
    @Environment(\.dismiss) private var dismiss
    @State private var digits = ""
    @State private var verified = false
    @State private var scanning = false
    /// A scanned fingerprint that differs from ours: said once the scanner has gone (an alert raised over a
    /// closing sheet is lost).
    @State private var mismatchPending = false
    @State private var mismatch = false

    private func grouped(_ s: String) -> String {
        stride(from: 0, to: s.count, by: 5).map { i -> String in
            let a = s.index(s.startIndex, offsetBy: i)
            let b = s.index(a, offsetBy: 5, limitedBy: s.endIndex) ?? s.endIndex
            return String(s[a..<b])
        }.joined(separator: " ")
    }
    /// The number stands on the secret of this correspondence. A stranger in the middle would have
    /// had to replace exactly that secret, and the number changes the moment they do — so comparing
    /// it out loud is comparing the one thing an attacker cannot leave alone. Both sides derive it
    /// from the same secret, so neither has to agree who reads first.
    private func compute() {
        guard let secret = MTPipeBook.secret(for: peerRef),
              let fp = MTPipe.fingerprint(secret: secret) else { digits = ""; return }
        digits = fp
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    Text(verified ? "✓ Identity verified" : "Not verified")
                        .font(.subheadline.bold())
                        .foregroundColor(verified ? .green : .gray)
                        .padding(.top, 8)
                    if !digits.isEmpty {
                        // We show OUR fingerprint: the peer scans it and checks it against their
                        // record about me. The scan below checks THEIR fingerprint against my record about them.
                        MontanaQRCode(payload: Data(("mt:fp:" + digits).utf8), side: 200, corner: 12)
                    }
                    Text(grouped(digits))
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.white).multilineTextAlignment(.center)
                        .padding(.horizontal)
                    Text("Compare these 60 digits with the other person (by voice or in person), or scan their QR. If they match, mark “Verified”.")
                        .font(.caption).foregroundColor(.gray)
                        .multilineTextAlignment(.center).padding(.horizontal)
                    VStack(spacing: 10) {
                        Button {
                            let on = !verified
                            SafetyStore.setVerified(peerRef, on); verified = on
                        } label: {
                            Text(verified ? "Unverify" : "Verified")
                                .frame(maxWidth: .infinity).padding(.vertical, 12)
                                .background(verified ? Color.gray.opacity(0.3) : Color.accentColor)
                                .foregroundColor(verified ? .white : .black)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        Button { scanning = true } label: {
                            Label("Scan the other person's QR", systemImage: "qrcode.viewfinder")
                                .frame(maxWidth: .infinity).padding(.vertical, 12)
                                .foregroundColor(Color.accentColor)
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.accentColor, lineWidth: 1))
                        }
                    }.padding(.horizontal)
                }.padding(.vertical)
            }
            .montanaPageGround()   // my page's ground, as every page wears it (26.09)
            .navigationTitle("Fingerprint verification").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { MontanaDoneMark { dismiss() } } }
            .sheet(isPresented: $scanning, onDismiss: {
                if mismatchPending { mismatchPending = false; mismatch = true }
            }) {
                NavigationStack {
                    QRScannerView { code in
                        // ONLY A FINGERPRINT IS COMPARED (23.09): any code in front of the lens — a card, a link, a
                        // label — unverified the conversation and closed the scanner. A code that is not a number of
                        // this shape says nothing about this person, and the scanner keeps looking. The code carries
                        // the correspondence FINGERPRINT, not an identity: nothing identifying reaches the screen.
                        var payload = code
                        if let h = payload.range(of: "#") { payload = String(payload[..<h.lowerBound]) }
                        if payload.hasPrefix("mt:fp:") { payload = String(payload.dropFirst(6)) }
                        guard !digits.isEmpty, payload.count == digits.count,
                              payload.allSatisfy({ $0.isASCII && $0.isNumber }) else {
                            MontanaP2PTrace.markFolded("fp_scan", "not a fingerprint len=\(code.count)", window: 10)
                            return
                        }
                        scanning = false
                        let same = payload == digits
                        SafetyStore.setVerified(peerRef, same); verified = same
                        if !same { mismatchPending = true }   // a different number is evidence, and it is said
                        MontanaP2PTrace.mark("fp_scan", same ? "match" : "mismatch")
                    }
                    .ignoresSafeArea()
                    .navigationTitle("Scan QR").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { MontanaCloseMark { scanning = false } } }
                }
            }
            .onAppear { compute(); verified = SafetyStore.isVerified(peerRef) }
            .alert("The codes do not match", isPresented: $mismatch) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("This is the code of another chat, or someone stands between you. Compare the digits by voice.")
            }
        }
    }
}

struct QRScannerView: UIViewControllerRepresentable {
    var onCode: (String) -> Void
    func makeCoordinator() -> Coord { Coord(onCode) }
    func makeUIViewController(context: Context) -> ScanVC {
        let vc = ScanVC(); vc.delegate = context.coordinator; return vc
    }
    func updateUIViewController(_ vc: ScanVC, context: Context) {}

    final class Coord: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        let onCode: (String) -> Void
        /// The last code handed on and when: the same code is handed on again only after two seconds.
        private var last: (code: String, at: Date)?
        init(_ c: @escaping (String) -> Void) { onCode = c }
        // A CODE IS HANDED ON EVERY TIME IT IS SHOWN ANEW (23.09, the author: «the tablet scanned T3 and the chat was not
        // made the first time»). The first code the camera saw latched this scanner for its whole life: a foreign code, or
        // one whose meeting failed, left it deaf to the right one while the picture still moved. The screen that asked
        // decides what a code means; here the same code, held in front of the lens, is handed on once in two seconds.
        func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput objects: [AVMetadataObject], from connection: AVCaptureConnection) {
            guard let o = objects.first as? AVMetadataMachineReadableCodeObject, let str = o.stringValue else { return }
            if let l = last, l.code == str, Date().timeIntervalSince(l.at) < 2 { return }
            last = (str, Date())
            DispatchQueue.main.async { self.onCode(str) }
        }
    }

    final class ScanVC: UIViewController {
        weak var delegate: AVCaptureMetadataOutputObjectsDelegate?
        private let session = AVCaptureSession()
        private var preview: AVCaptureVideoPreviewLayer?
        /// THE SESSION HAS ONE OWNER, ITS QUEUE (23.09): the start ran on a global queue and the stop on the main one, and
        /// the stop read «running» before a slow start had finished -- a scanner closed at once kept the camera on with
        /// nothing on the screen until the controller was released. Start and stop now stand in one line, in order.
        private let sessionQueue = DispatchQueue(label: "montana.scanner.session", qos: .userInitiated)

        /// A black rectangle with no explanation reads as a broken app. The refusal's cause
        /// goes to the journal, and the person is told the scanner did not open — in the platform's own empty state.
        private func showCameraUnavailable(_ why: String) {
            E2ELog.write("scanner: \(why)")
            MontanaP2PTrace.mark("scan_camera", "unavailable why=\(why)")
            var c = UIContentUnavailableConfiguration.empty()
            c.image = UIImage(systemName: "video.slash")
            c.text = String(localized: "The camera is unavailable.", bundle: MTLanguage.bundle)
            contentUnavailableConfiguration = c
        }
        /// A camera this app may not use: the words the call screen says, and the one road to Settings — none when
        /// the device's owner restricted the camera, which Settings of this app cannot lift.
        private func showCameraOff() {
            let status = AVCaptureDevice.authorizationStatus(for: .video)
            E2ELog.write("scanner: the camera is off for this app (status \(status.rawValue))")
            MontanaP2PTrace.mark("scan_camera", "off status=\(status.rawValue)")
            var c = UIContentUnavailableConfiguration.empty()
            c.image = UIImage(systemName: "video.slash")
            c.text = String(localized: "Camera is off for Montana", bundle: MTLanguage.bundle)
            if status == .denied {
                var b = UIButton.Configuration.filled()
                b.buttonSize = .large
                b.title = String(localized: "Open Settings", bundle: MTLanguage.bundle)
                c.button = b
                c.buttonProperties.primaryAction = UIAction { _ in MontanaSystemSettings.open() }
            }
            contentUnavailableConfiguration = c
        }
        /// Whether the scanner is on the screen: a camera allowed after it left is not turned on for nobody.
        private var shown = false
        override func viewDidLoad() {
            super.viewDidLoad(); view.backgroundColor = .black
            overrideUserInterfaceStyle = .dark   // a dark surface: the platform's own colours resolve on it
            // THE CAMERA IS ASKED FIRST, AND A REFUSAL HAS A ROAD (23.09): the scanner opened the camera blind — a
            // phone that had refused it read «the camera is unavailable» with nothing to do about it. The platform's
            // own question comes first; a refusal stands in the platform's own empty state with its road to Settings.
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized: build()
            case .notDetermined:
                AVCaptureDevice.requestAccess(for: .video) { [weak self] ok in
                    DispatchQueue.main.async {
                        guard let self else { return }
                        MontanaP2PTrace.mark("scan_camera", "asked granted=\(ok ? 1 : 0)")
                        if ok { self.build(); if self.shown { self.start() } } else { self.showCameraOff() }
                    }
                }
            default: showCameraOff()
            }
        }
        private func build() {
            guard let dev = AVCaptureDevice.default(for: .video) else { showCameraUnavailable("no camera"); return }
            guard let input = try? AVCaptureDeviceInput(device: dev) else { showCameraUnavailable("camera input not created"); return }
            guard session.canAddInput(input) else { showCameraUnavailable("the session refused the camera input"); return }
            session.addInput(input)
            let out = AVCaptureMetadataOutput()
            guard session.canAddOutput(out) else { showCameraUnavailable("the session refused the scanner output"); return }
            session.addOutput(out)
            out.setMetadataObjectsDelegate(delegate, queue: .main)
            out.metadataObjectTypes = [.qr]
            let p = AVCaptureVideoPreviewLayer(session: session)
            p.videoGravity = .resizeAspectFill; p.frame = view.bounds
            view.layer.addSublayer(p); preview = p
        }
        private func start() {
            sessionQueue.async { [session] in if !session.isRunning, !session.inputs.isEmpty { session.startRunning() } }
        }
        override func viewWillAppear(_ a: Bool) {
            super.viewWillAppear(a)
            shown = true
            start()
            MontanaScreenAwake.hold("scanner")   // the screen stays awake while the scanner looks (18.09)
        }
        override func viewWillDisappear(_ a: Bool) {
            super.viewWillDisappear(a)
            shown = false
            MontanaScreenAwake.release("scanner")
            sessionQueue.async { [session] in if session.isRunning { session.stopRunning() } }
        }
        override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews(); preview?.frame = view.bounds }
    }
}

// New device: show the QR and wait for the key transfer.
struct LinkShowQRView: View {
    @State private var offerText: String?
    @State private var linked = false
    var body: some View {
        VStack(spacing: 20) {
            if linked {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 64)).foregroundColor(.green)
                Text("Device linked").foregroundColor(.white).font(.title3.bold())
                Text("Your chat history has been transferred to this device.").foregroundColor(.gray).multilineTextAlignment(.center).padding(.horizontal)
            } else {
                Text("Show this code to a phone where Montana is already running").foregroundColor(.white).multilineTextAlignment(.center).padding(.horizontal)
                if let offerText {
                    MontanaQRCode(payload: Data(offerText.utf8), side: 240, corner: 12)
                }
                ProgressView()
                Text("Waiting to link…").foregroundColor(.gray).font(.caption)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).montanaPageGround()   // my page's ground, as every page wears it (26.09)
        .onAppear {
            if let offer = E2E.shared.beginLinkOnNewDevice(),
               let blob = try? JSONEncoder().encode(offer),
               let str = String(data: blob, encoding: .utf8) {
                offerText = str
            }
            E2E.shared.onKeyLinked = { withAnimation { linked = true } }
        }
        .onDisappear { E2E.shared.onKeyLinked = nil; E2E.shared.cancelLink() }
        .navigationTitle("Link this device").navigationBarTitleDisplayMode(.inline)
    }
}

// Old device: scan the new one's QR, confirm, send the key.
struct LinkScanView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var pending: LinkOffer?
    @State private var result: String?
    var body: some View {
        ZStack {
            QRScannerView { code in
                guard pending == nil, result == nil,
                      let d = code.data(using: .utf8),
                      let o = try? JSONDecoder().decode(LinkOffer.self, from: d) else { return }
                pending = o
            }.ignoresSafeArea()
            VStack {
                Spacer()
                Text("Point at the new device's QR code")
                    .foregroundColor(.white).padding(10).background(.black.opacity(0.6)).cornerRadius(10).padding(.bottom, 40)
            }
        }
        .navigationTitle("Link device").navigationBarTitleDisplayMode(.inline)
        .alert("Transfer chat history to the new device?", isPresented: Binding(get: { pending != nil }, set: { v in if !v { pending = nil } })) {
            Button("Transfer") { if let o = pending { pending = nil; send(o) } }
            Button("Cancel", role: .cancel) { pending = nil }
        } message: { Text("The history key travels straight from device to device.") }
        .alert("Linking", isPresented: Binding(get: { result != nil }, set: { v in if !v { result = nil; dismiss() } })) {
            Button("OK", role: .cancel) { result = nil; dismiss() }
        } message: { Text(result ?? "") }
    }
    func send(_ o: LinkOffer) {
        Task {
            let ok = await E2E.shared.sendLinkGrant(to: o)
            await MainActor.run { result = ok ? "Done. The key was sent to the new device." : "Sending failed. Please try again." }
        }
    }
}

// Scan a one-time card or a name code and open the correspondence it begins.
struct ScanMeetingView: View {
    var onFound: (String) -> Void   // the local reference of the correspondence
    @State private var done = false
    /// What the meeting answered when it did not open — said to the face, as the link's road says it.
    @State private var verdict: String?
    var body: some View {
        ZStack {
            QRScannerView { code in
                guard !done else { return }
                // Only a one-time card or a name code: parsed by the ONE introduction
                // resolver — the same as for links and pasted strings. There is no second
                // copy of the parser.
                if case .refused = MontanaConv.meeting(fromInput: code) {
                    MontanaP2PTrace.markFolded("scan_code", "not an introduction len=\(code.count)", window: 10)
                    return
                }
                done = true
                MontanaP2PTrace.mark("scan_code", "an introduction -- meeting")
                Task {
                    let out = await MontanaMeeting.meet(code)
                    await MainActor.run {
                        // A MEETING THAT DID NOT OPEN IS SAID (23.09): the scanner stood silent and the person held the
                        // code in front of it without knowing why nothing happened. The words are the link road's own.
                        switch out {
                        case .opened(let ref): onFound(ref)
                        case .spent: verdict = "Invitation expired. Ask for a new code."
                        case .refused: verdict = "The invitation could not be opened. Check the link or try again."
                        case .nameless: verdict = "Nobody holds this name."
                        case .ownName: verdict = "This is your own name."
                        }
                    }
                }
            }.ignoresSafeArea()
            VStack {
                Spacer()
                Text("Point at a one-time card or a @username code")
                    .foregroundColor(.white).padding(10).background(.black.opacity(0.6)).cornerRadius(10).padding(.bottom, 40)
            }
        }
        .navigationTitle("Scan code").navigationBarTitleDisplayMode(.inline)
        // Closing the verdict lets the scanner take a code again.
        .alert(Text(LocalizedStringKey(verdict ?? "")), isPresented: Binding(
            get: { verdict != nil }, set: { if !$0 { verdict = nil; done = false } })) {
            Button("OK", role: .cancel) { verdict = nil; done = false }
        }
    }
}

// Show the secret phrase (24 words) sovereign mode.
struct SeedShowView: View {
    @State private var words: [String] = []
    @State private var copied = false
    @State private var authed = false
    @State private var authFailed = false
    @State private var acked = false
    @State private var noDeviceAuth = false
    @State private var ack1 = false
    @State private var ack2 = false
    func requestAuth() {
        let ctx = LAContext(); var err: NSError?
        if ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) {
            ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Show secret phrase") { ok, _ in
                DispatchQueue.main.async {
                    if ok { authed = true; authFailed = false; words = MontanaSeed.mnemonic?.split(separator: " ").map(String.init) ?? [] }
                    else { authFailed = true }
                }
            }
        } else {
            // AN ABSENT CHECK IS A FAILED CHECK. «Show the phrase» used to stand here, and it
            // was a hole: `canEvaluatePolicy(.deviceOwnerAuthentication)` answers false in
            // EXACTLY one case — the phone has no passcode at all. That is, the twenty-four
            // words the whole account restores from opened to anyone who picked up the phone.
            // Nothing to verify with — nothing may be shown, and the person is told why.
            authFailed = true
            noDeviceAuth = true
            E2ELog.write("seed: device has no passcode — the phrase is not shown")
        }
    }
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if !authed {
                    Image(systemName: "lock.fill").font(.system(size: 44)).foregroundColor(Color.accentColor).padding(.top, 48)
                    Text(noDeviceAuth ? "Set a passcode on this device — without it the phrase cannot be protected." : (authFailed ? "Verification failed." : "Confirm with your device passcode or biometrics to reveal the secret phrase."))
                        .foregroundColor(.gray).font(.footnote).multilineTextAlignment(.center).padding(.horizontal)
                    Button { requestAuth() } label: {
                        Text("Unlock").bold().foregroundColor(.black)
                            .frame(maxWidth: .infinity).padding().background(Color.accentColor).cornerRadius(12)
                    }.padding(.horizontal, 28)
                } else if !acked {
                    Image(systemName: "shield.lefthalf.filled")
                        .font(.system(size: 72)).foregroundColor(Color.accentColor).padding(.top, 36)
                    Label("This information is for you only!", systemImage: "exclamationmark.triangle")
                        .font(.headline).foregroundColor(.white).padding(.top, 8)
                    Text("This seed phrase unlocks access to your wallet")
                        .font(.title2.bold()).foregroundColor(.white)
                        .multilineTextAlignment(.center).padding(.horizontal, 24)
                    Button { ack1.toggle() } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: ack1 ? "checkmark.square.fill" : "square")
                                .font(.title3).foregroundColor(ack1 ? .green : .gray)
                            Text("Montana has no access to this key.")
                                .foregroundColor(.white).multilineTextAlignment(.leading)
                            Spacer()
                        }.padding(14).background { MTGlassCardPlate(cornerRadius: 12) }.clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .contentShape(Rectangle())   // the whole row is the target, not only its words (22.09)
                    }.padding(.horizontal, 20).padding(.top, 12)
                    Button { ack2.toggle() } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: ack2 ? "checkmark.square.fill" : "square")
                                .font(.title3).foregroundColor(ack2 ? .green : .gray)
                            Text("Don't store this information digitally — write it on paper and keep it in a safe place.")
                                .foregroundColor(.white).multilineTextAlignment(.leading)
                            Spacer()
                        }.padding(14).background { MTGlassCardPlate(cornerRadius: 12) }.clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .contentShape(Rectangle())   // the whole row is the target, not only its words (22.09)
                    }.padding(.horizontal, 20)
                    Button { acked = true } label: {
                        Text("Continue").bold()
                            .foregroundColor(ack1 && ack2 ? .black : .gray)
                            .frame(maxWidth: .infinity).padding()
                            .background(ack1 && ack2 ? Color.accentColor : Color(white: 0.2))
                            .clipShape(Capsule())
                    }
                    .disabled(!(ack1 && ack2))
                    .padding(.horizontal, 20).padding(.top, 16)
                } else {
                Text("Write down these 24 words in order and keep them offline. They restore your history if you lose all your devices. Don't show them to anyone.")
                    .foregroundColor(.gray).font(.footnote).multilineTextAlignment(.center).padding(.horizontal)
                if words.isEmpty {
                    Text("No active seed found.").foregroundColor(.gray).padding(.top, 40)
                } else {
                    let half = (words.count + 1) / 2
                    let order = (0..<half).flatMap { r -> [Int] in (r + half < words.count) ? [r, r + half] : [r] }
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        ForEach(order, id: \.self) { i in
                            HStack(spacing: 6) {
                                Text("\(i+1).").foregroundColor(.gray).frame(width: 26, alignment: .trailing)
                                Text(words[i]).foregroundColor(.white).bold()
                                Spacer()
                            }.padding(8).background { MTGlassCardPlate(cornerRadius: 8) }.clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                    }.padding(.horizontal)
                    Button {
                        UIPasteboard.general.string = words.joined(separator: " ")
                        withAnimation { copied = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { withAnimation { copied = false } }
                    } label: {
                        Label(copied ? "Copied" : "Copy",
                              systemImage: copied ? "checkmark" : "doc.on.doc")
                            .bold().foregroundColor(copied ? .green : Color.accentColor)
                    }
                }
                }
            }.padding(.vertical)
        }
        .montanaPageGround()   // my page's ground, as the drawer and my page wear it (25.09)
        .navigationTitle("Secret phrase").navigationBarTitleDisplayMode(.inline)
        .onAppear { requestAuth() }
    }
}

// Restore history from the secret phrase.
struct SeedRestoreView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var input = ""
    @State private var msg: String?
    var body: some View {
        VStack(spacing: 16) {
            Text("Enter the 24 words separated by spaces. Your history will switch to private mode and be restored from the phrase.")
                .foregroundColor(.gray).font(.footnote).multilineTextAlignment(.center).padding(.horizontal)
            TextEditor(text: $input).frame(height: 140).padding(8).background(Color(white: 0.12)).cornerRadius(10)
                .foregroundColor(.white).autocorrectionDisabled().textInputAutocapitalization(.never).padding(.horizontal)
            Button {
                let ws = input.lowercased().split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "," }).map(String.init)
                if ws.count != 24 { msg = "Exactly 24 words required (entered \(ws.count))."; return }
            } label: { Text("Restore").bold().frame(maxWidth: .infinity) }
                .padding().background(Color.accentColor).foregroundColor(.black).cornerRadius(12).padding(.horizontal)
            Spacer()
        }.padding(.top).montanaPageGround()   // my page's ground, as every page wears it (26.09)
        .navigationTitle("Restore from phrase").navigationBarTitleDisplayMode(.inline)
        .alert(msg ?? "", isPresented: Binding(get: { msg != nil }, set: { v in if !v { let ok = msg?.hasPrefix("Done") ?? false; msg = nil; if ok { dismiss() } } })) {
            Button("OK", role: .cancel) {}
        }
    }
}

// Choose the history privacy mode (regular server vs sovereign mode).
// Chat folders
struct ChatFolder: Identifiable {
    let id = UUID()
    var name: String
}

// A nice animated "folders picture" at the top
struct AnimatedFoldersHeader: View {
    @State private var animate = false
    var body: some View {
        ZStack {
            Image(systemName: "folder.fill")
                .font(.system(size: 52))
                .foregroundColor(Color.accentColor.opacity(0.35))
                .rotationEffect(.degrees(animate ? -14 : -8))
                .offset(x: -26, y: 6)
            Image(systemName: "folder.fill")
                .font(.system(size: 56))
                .foregroundColor(Color.accentColor.opacity(0.6))
                .rotationEffect(.degrees(animate ? 12 : 7))
                .offset(x: 26, y: 6)
            Image(systemName: "folder.fill")
                .font(.system(size: 66))
                .foregroundColor(Color.accentColor)
                .scaleEffect(animate ? 1.06 : 0.95)
                .shadow(color: Color.accentColor.opacity(0.5), radius: animate ? 14 : 4)
        }
        .frame(height: 120)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.3).repeatForever(autoreverses: true)) {
                animate = true
            }
        }
    }
}

// folder screen: renaming + chat selection
struct FolderDetailView: View {
    @Binding var folder: ChatFolder
    @State private var included: Set<String> = []
    private let testMode = false
    var allChats: [String] { [] }
    var body: some View {
        List {
            Section("Folder name") {
                TextField("Title", text: $folder.name).foregroundColor(.white)
            }.listRowBackground(MTGlassRowPlate())
            Section("Chats in folder") {
                ForEach(allChats, id: \.self) { c in
                    Button {
                        if included.contains(c) { included.remove(c) } else { included.insert(c) }
                    } label: {
                        HStack {
                            Text(c).foregroundColor(.white)
                            Spacer()
                            Image(systemName: included.contains(c) ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(included.contains(c) ? Color.accentColor : .gray)
                        }
                        .contentShape(Rectangle())   // the whole row is the target, not only its words (22.09)
                    }
                }
            }.listRowBackground(MTGlassRowPlate())
        }
        .scrollContentBackground(.hidden).montanaPageGround()   // my page's ground, as every page wears it (26.09)
        .navigationTitle(folder.name).navigationBarTitleDisplayMode(.inline)
    }
}

// Ask a question
struct SupportView: View {
    // A REAL DOOR (Guideline 1.2, the author's word 15.09): the addresses are shown as they
    // are and a tap opens the mail. The old screen took a question and threw it away.
    @State private var composing: (to: String, subject: String)? = nil
    @State private var copied = false
    private func write(_ to: String, _ subject: String) {
        if MFMailComposeViewController.canSendMail() { composing = (to, subject) }
        else if let u = MontanaSafety.mailto(to, subject: subject, body: ""), UIApplication.shared.canOpenURL(u) { UIApplication.shared.open(u) }
        else { UIPasteboard.general.string = to; copied = true }
    }
    var body: some View {
        List {
            Section("Write to us") {
                Button { write(MontanaSafety.supportMail, String(localized: "Montana question", bundle: MTLanguage.bundle)) } label: {
                    HStack { Text("Ask a question").foregroundColor(.white); Spacer(); Text(verbatim: MontanaSafety.supportMail).foregroundColor(.gray).font(.footnote) }   // USER-DATA: an address
                    .contentShape(Rectangle())   // the whole row is the target, not only its words (22.09)
                }
                Button { write(MontanaSafety.abuseMail, String(localized: "Montana report", bundle: MTLanguage.bundle)) } label: {
                    HStack { Text("Report inappropriate activity").foregroundColor(.white); Spacer(); Text(verbatim: MontanaSafety.abuseMail).foregroundColor(.gray).font(.footnote) }   // USER-DATA: an address
                    .contentShape(Rectangle())   // the whole row is the target, not only its words (22.09)
                }
                Link(destination: URL(string: MontanaSafety.site)!) {
                    HStack { Text("Website").foregroundColor(.white); Spacer(); Text(verbatim: MontanaSafety.site).foregroundColor(.gray).font(.footnote) }   // USER-DATA: an address
                }
            }.listRowBackground(MTGlassRowPlate())
            Section {
                Text("Reports of objectionable content are reviewed within 24 hours.").font(.footnote).foregroundColor(.gray)
            }.listRowBackground(MTGlassRowPlate())
        }
        .scrollContentBackground(.hidden).montanaPageGround()   // my page's ground, as the drawer and my page wear it (25.09)
        .navigationTitle("Ask a question").navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: Binding(get: { composing != nil }, set: { if !$0 { composing = nil } })) {
            if let c = composing { MTMailComposer(to: c.to, subject: c.subject, body: "") }
        }
        .alert("No mail account on this phone. The address is copied.", isPresented: $copied) { Button("OK", role: .cancel) {} }
    }
}



// ════════════════════════════════════════════════════════════
// CREATE A GROUP
// ════════════════════════════════════════════════════════════
/// THE GROUP IS BORN IN TWO STEPS, as the platform's messengers make it (the author's word 05.10.2026: «choose Contacts to add to
/// the group, see the mechanics in the reference tree»): the people first, each chosen by a tick, then the group's name and face and the tick
/// that creates it. Only a person this phone holds a pipe with stands in the list: a group letter rides each member's own pipe,
/// and a person without one could be shown as a member and never receive a word.
struct MTGroupPickStep: View {
    @EnvironmentObject private var store: ChatStore
    @Environment(\.dismiss) private var dismiss
    /// The group people are added to from its page (MTGroup.add): its own people are not listed, and the tick ends the choosing.
    var adding: String? = nil
    var onCreate: (String, Data, [Chat]) -> Void
    @State private var chosen: [String] = []
    @State private var query = ""
    @State private var naming = false

    private var people: [Chat] { Self.reachable(store, adding: adding) }
    /// Only a person this phone holds a pipe with: a letter of a group or a channel rides each person's own pipe; adding to a
    /// group, its own people are not listed again.
    static func reachable(_ store: ChatStore, adding: String? = nil) -> [Chat] {
        store.listChats().filter { c in
            !c.isGroup && c.convId != nil && !ChatStore.isLocalRoom(c.name) && MontanaConv.holds(c.convRef) && !ChatStore.refusesCold(c.convRef)
                && !(adding.map { MTGroup.shared.carries(to: c.convRef, in: $0) } ?? false)
        }
    }
    private var shown: [Chat] {
        let q = query.trimmingCharacters(in: .whitespaces)
        return q.isEmpty ? people : people.filter { store.title(for: $0).localizedCaseInsensitiveContains(q) }
    }
    private var chosenChats: [Chat] { chosen.compactMap { ref in people.first { $0.convRef == ref } } }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(shown) { c in
                        Button { toggle(c.convRef) } label: {
                            MTPickRow(chat: c, on: chosen.contains(c.convRef))
                        }
                    }
                } footer: {
                    Text("A group letter rides the pipe of each person, so only the people you write with are listed.")
                }
                .listRowBackground(MTGlassRowPlate())
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always))
            .scrollContentBackground(.hidden).montanaPageGround()
            .navigationTitle("Choose members").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { MontanaCloseMark { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    MontanaDoneMark {
                        if adding != nil { onCreate("", Data(), chosenChats); dismiss() } else { naming = true }
                    }.disabled(chosen.isEmpty).opacity(chosen.isEmpty ? 0.4 : 1)
                }
            }
            .navigationDestination(isPresented: $naming) {
                MTGroupNameStep(members: chosenChats) { title, face in
                    onCreate(title, face, chosenChats)
                    dismiss()
                }
            }
        }
    }

    private func toggle(_ ref: String) {
        if let i = chosen.firstIndex(of: ref) { chosen.remove(at: i) } else { chosen.append(ref) }
    }
}

/// THE GROUP PAGE'S QUESTIONS, ASKED BY THE PLATFORM (MontanaPeerInfoScreen): a member leaving, the owner taking a person out,
/// the owner adding people -- each a word to every phone of the group (MTGroup.leave, remove, add).
struct MTGroupPageAsks: ViewModifier {
    @EnvironmentObject private var store: ChatStore
    let chat: Chat
    @Binding var confirmLeave: Bool
    @Binding var removingSeat: String?
    @Binding var addingPeople: Bool
    @Binding var confirmDissolve: Bool
    /// The page and its chat close once the group has left this phone (left and deleted, or deleted for everyone).
    var onGone: () -> Void = {}

    func body(content: Content) -> some View {
        let channel = MTGroup.shared.kind(chat.name) == .channel
        let title = store.title(for: chat)
        content
            // LEAVE GROUP (the reference folder: «Are you sure you want to leave and delete %@?»): the owner is told, the chat goes
            .confirmationDialog(channel ? Text("Leave the channel?") : Text("Are you sure you want to leave and delete \(title)?"),
                                isPresented: $confirmLeave, titleVisibility: .visible) {
                if channel {
                    Button(role: .destructive) { MTGroup.shared.leave(chat.name, store: store) } label: { Text("Leave channel") }
                } else {
                    Button(role: .destructive) { MTGroup.shared.leaveAndErase(chat.name, store: store); onGone() } label: { Text("Leave Group") }
                }
            }
            // DELETE GROUP (the reference folder: «Delete for All»): every member's copy goes with the owner's
            .confirmationDialog(Text("Are you sure you want to delete the group \(title) and all of its messages for all members of the group?"),
                                isPresented: $confirmDissolve, titleVisibility: .visible) {
                Button(role: .destructive) { MTGroup.shared.dissolve(chat.name, store: store); onGone() } label: { Text("Delete for All") }
            }
            .confirmationDialog("Remove from the group?",
                                isPresented: Binding(get: { removingSeat != nil }, set: { if !$0 { removingSeat = nil } }),
                                titleVisibility: .visible) {
                Button("Remove", role: .destructive) {
                    if let seat = removingSeat { MTGroup.shared.kick(chat.name, seat: seat, store: store) }   // the owner's hand, or an administrator's ask (R.6)
                    removingSeat = nil
                }
            }
            .sheet(isPresented: $addingPeople) {
                MTGroupPickStep(adding: chat.name) { _, _, people in MTGroup.shared.add(chat.name, people: people, store: store) }
                    .environmentObject(store)
            }
    }
}

/// The second step: the group's face and name above the people chosen, and the tick that creates it.
struct MTGroupNameStep: View {
    @EnvironmentObject private var store: ChatStore
    let members: [Chat]
    var onCreate: (String, Data) -> Void
    @State private var name = ""
    @State private var face = Data()
    @FocusState private var typing: Bool

    private var title: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    MTFacePicker(face: $face)
                    TextField("Group name", text: $name).focused($typing)
                }
            }
            .listRowBackground(MTGlassRowPlate())
            Section("Members") {
                ForEach(members) { c in
                    HStack(spacing: 12) {
                        MTChatAvatar(chat: c, size: 40)
                        Text(verbatim: store.title(for: c))   // USER-DATA: a person's name
                    }
                    .frame(minHeight: 44)
                }
            }
            .listRowBackground(MTGlassRowPlate())
        }
        .scrollContentBackground(.hidden).montanaPageGround()
        .navigationTitle("New Group").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                MontanaDoneMark { onCreate(title, face) }.disabled(title.isEmpty).opacity(title.isEmpty ? 0.4 : 1)
            }
        }
        .onAppear { typing = true }
    }
}
