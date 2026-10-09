//
//  MontanaApp.swift
//  Montana
//

#if targetEnvironment(macCatalyst)
import ServiceManagement   // the retired VPN supervisor leaves launchd (MTRetiredSupervisor)
#endif
import SwiftUI
import BackgroundTasks
import UserNotifications
import UIKit
import Darwin
import MachO
import Network
import MetricKit

@main
enum MontanaEntry {
    @MainActor static func main() {
        #if targetEnvironment(macCatalyst)
        // THE RETIRED SUPERVISOR LEAVES LAUNCHD (the critic 08.10.2026, N5): a Mac that ran an earlier build keeps a login agent
        // that starts this app with «--vpn-supervisor» and starts it again whenever it ends. The VPN left for its own app: such
        // a start takes the agent off launchd and leaves, opening no window.
        if ProcessInfo.processInfo.arguments.contains("--vpn-supervisor") { MTRetiredSupervisor.leave() }
        #endif
        MontanaApp.main()
    }
}

struct MontanaApp: App {
    @State private var langTick = 0
    @State private var meetVerdict: String?   // the loud outcome of a meeting by link (F-4)
    @AppStorage("AppLanguage") private var appLang = ""   // "" = follow system
    init() {
        // Before any screen: an installation that has just appeared must not inherit a person.
        MontanaInstall.forgetLeftoverSeed { SeedScope.forget() }
        MTSeats.launch()   // a move between seats the last run did not finish is finished before any owner is born (the second identity checklist, 1.3)
        BT.dropStale()   // the bubble defaults' generation (the reference for everyone)
        _ = LocalizedBundle.install; MTLanguage.mirror(); MontanaP2PTrace.markOnce("app_init")
        MontanaVoiceOrb.warm()   // the orb's pipelines, off the main thread, before any chat asks
    }   // swap the localization bundle for live language switching (UIKit/NSE)
    // SwiftUI Text resolves the String Catalog via environment locale — the native path for a live in-app switch.
    private var appLocale: Locale { _ = appLang; return MTLanguage.locale }   // the one language (MTLanguage)
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    var body: some Scene {
        WindowGroup {
            // THE SYSTEM TEXT SIZE CHANGES THE LETTERS OF A MESSAGE, NOT THE SHAPE OF ANYTHING
            // (the author's word 11.09: «changing the font size must distort nothing» — on an
            // iPhone 17 with a large setting the reactions, the buttons in the chat and the bubble
            // menu went crooked). The clamp on buttons alone was not enough: a reaction chip, a
            // menu row, a caption are geometry too. So every window is pinned to the canonical
            // step at its trait (MontanaTextSize) — one place for the whole tree, hosted windows
            // and cells included — and only the letters of a letter ask for the person's size by name.
            MontanaTypeSizeGate {
                RootView()
                    .montanaRoot()
                    .environment(\.locale, appLocale)   // drives SwiftUI Text localization to the chosen language
                .id(langTick)   // redraw the whole tree on language change (live)
                .onReceive(NotificationCenter.default.publisher(for: .appLanguageChanged)) { _ in langTick += 1 }
                .onOpenURL { url in
                    // The whole road of a link is ONE entrance: the trace mark, the scheme case, the
                    // normalization, the identity guard, the meeting by one resolver and the loud outcome (F-4..F-8).
                    MontanaMeeting.handleLink(url)
                }
                // THE CAMERA'S CODE IS A WEB LINK, AND A WEB LINK ARRIVES AS AN ACTIVITY (23.09, the author: «T2 scans T3's
                // permanent code with the ordinary camera, it throws me into the app and makes no chat»). The system camera
                // opens https://montana.quest/perp/... as a universal link; T2 at 20:15:17 and the tablet at 20:15:59 and
                // 20:16:26 came to the foreground and not one line said a link had come -- the activity never reached the
                // entrance. It is handed to the same one entrance here; a link that also comes by another door is handled once.
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { ua in
                    if let u = ua.webpageURL { MontanaMeeting.handleLink(u) }
                    else { MontanaP2PTrace.mark("link_refused", "why=web-activity-without-url") }
                }
                .onReceive(NotificationCenter.default.publisher(for: .montanaMeetVerdict)) { n in
                    meetVerdict = n.userInfo?["msg"] as? String
                }
                .alert(Text(LocalizedStringKey(meetVerdict ?? "")), isPresented: Binding(
                    get: { meetVerdict != nil }, set: { if !$0 { meetVerdict = nil } })) {
                    Button("OK", role: .cancel) { meetVerdict = nil }
                }
            }
        }
    }
}

/// THE SHAPE OF THE APP DOES NOT FOLLOW THE SYSTEM TEXT SIZE (the author's word 11.09). Every
/// window is pinned to the canonical step at its trait — the pin reaches every view and every
/// hosted controller under the window, so a reaction chip, a menu row, a call button keep their
/// geometry whatever the setting. The person's own step is remembered here, in one place
/// ([I-10]), and the only thing that asks for it is the letters of a message.
enum MontanaTextSize {
    static let canonical: UIContentSizeCategory = .large
    /// The same step for SwiftUI's environment — one value, two spellings the two frameworks read.
    static let lock: DynamicTypeSize = DynamicTypeSize(canonical) ?? .large
    private(set) static var system: DynamicTypeSize = .large
    private(set) static var category: UIContentSizeCategory = .large
    static func remember() {
        category = UIApplication.shared.preferredContentSizeCategory
        system = DynamicTypeSize(category) ?? .large
    }
    static func pin(_ w: UIWindow) { w.traitOverrides.preferredContentSizeCategory = canonical }
    static func pinAll() {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }.forEach(pin)
    }
    /// The letters of a message — the one font that follows the person's setting.
    static func letterFont(_ style: UIFont.TextStyle) -> UIFont {
        UIFont.preferredFont(forTextStyle: style,
                             compatibleWith: UITraitCollection(preferredContentSizeCategory: category))
    }
}

/// The gate: it remembers the person's setting from the application (the window's own trait is
/// pinned and cannot say) and pins every window, at entry and again whenever the setting changes.
struct MontanaTypeSizeGate<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        content.onAppear { MontanaTextSize.remember(); MontanaTextSize.pinAll() }
            .onReceive(NotificationCenter.default.publisher(for: UIContentSizeCategory.didChangeNotification)) { _ in
                MontanaTextSize.remember(); MontanaTextSize.pinAll()
            }
    }
}

extension View {
    /// Text that IS SUPPOSED to grow: it is the very thing the person changed the setting for.
    func montanaTextScale() -> some View { dynamicTypeSize(MontanaTextSize.system) }
}

/// A button does not change shape. The caption inside is drawn at the canonical step, so the box
/// does not breathe along with the font setting: rows do not spread, neighbours are not squeezed out,
/// and the button stays where and as the person remembers it. The style is applied once at the root
/// and reaches every button of the tree through the environment -- there is no second place for this.
struct MontanaShapeKeeper: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .dynamicTypeSize(MontanaTextSize.lock)
            .opacity(configuration.isPressed ? 0.55 : 1)
    }
}

/// THE ONE DOOR A HOSTED ROOT IS BORN THROUGH (the author's word 11.09: «nothing but the letters
/// changes with the font size»). The lock of the type step and the shape-keeping button style live
/// on the ROOT of a SwiftUI tree; a tree hosted in a window or a UIKit view of its own — the bubble
/// menu, the call, the emoji panel, the photo viewer, the coin — is a root of its own and used to be
/// born naked: the UIKit trait pin does not reach SwiftUI's environment (the voice title inside the
/// menu grew with the setting), and without the style the system drew its own glass capsules under
/// every button of the menu and clipped the reactions to them (1468). Every hosting controller is
/// made here, so a naked root cannot be born; the layout guard counts the births (section 7).
enum MontanaHost {
    static func root<V: View>(_ v: V) -> AnyView { AnyView(v.montanaRoot()) }
    static func make<V: View>(_ v: V) -> UIHostingController<AnyView> {
        let h = UIHostingController(rootView: root(v))
        born(h, V.self)
        return h
    }
    /// THE ONE UPDATE OF A HOSTED ROOT (24.09, the author's word: «close the whole class at the root, and let the guard
    /// not allow it»). A host born here and handed a root of another type at an update loses its whole tree — under
    /// AnyView the platform destroys the old hierarchy when the wrapped type changes. The open chat's host did exactly
    /// that at its first update (a bare AnyView against the birth's montanaRoot), and the profile, the post's sheet, the
    /// sticker panel, the business card and the focused field went with it: each worked only the second time. Every
    /// update passes here — built by the same hand as the birth — and a type other than the birth's is said in the
    /// diary (host_drift) with the host's name the moment it happens; the owner guard lets no root be set anywhere
    /// else and holds each update to the shape of its birth. `replaces` — a host that shows different trees by design
    /// (the menu window).
    static func reroot<V: View>(_ h: UIHostingController<AnyView>, _ v: V, why: String, replaces: Bool = false) {
        let now = ObjectIdentifier(V.self)
        if let was = objc_getAssociatedObject(h, &bornKey) as? MTBornType, was.id != now {
            if !replaces {
                MontanaP2PTrace.mark("host_drift", "\(why) type=\(String(String(describing: V.self).prefix(80))) — the hosted tree is built anew at this update")
            }
            born(h, V.self)
        }
        h.rootView = root(v)
    }
    /// The birth's type, kept on the host: a subclass born with a root of its own names it here too.
    static func born<V>(_ h: UIHostingController<AnyView>, _ t: V.Type) {
        objc_setAssociatedObject(h, &bornKey, MTBornType(ObjectIdentifier(t)), .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
    nonisolated(unsafe) private static var bornKey: UInt8 = 0
}
/// The type a host's root was born with (MontanaHost.reroot compares against it).
final class MTBornType { let id: ObjectIdentifier; init(_ id: ObjectIdentifier) { self.id = id } }
extension View {
    /// What every root of the tree wears: the canonical type step and the shape-keeping buttons.
    func montanaRoot() -> some View { dynamicTypeSize(MontanaTextSize.lock).buttonStyle(MontanaShapeKeeper()) }
}

extension Notification.Name {
    static let openChatRequest = Notification.Name("openChatRequest")
    /// The player bar's way back to a letter in another chat (chat, file) — the list opens it there.
    static let montanaGoToLetter = Notification.Name("montanaGoToLetter")
    static let montanaRemirror = Notification.Name("montanaRemirror")
    /// The identity has gone into storage. One announcement for the whole client: the network core
    /// listens to it and rises by itself instead of depending on somebody else's screen.
    static let montanaSeedOpened = Notification.Name("montanaSeedOpened")
    /// The chat list was changed NOT by a screen -- the peer erased a conversation. The screen re-reads the list.
    static let montanaChatsChanged = Notification.Name("montanaChatsChanged")
    /// The outcome of a meeting by link, which must reach the person -- not the journal (F-4).
    static let montanaMeetVerdict = Notification.Name("montanaMeetVerdict")
    /// A correspondent's daily link arrived (their answer to «share contact»); userInfo["conv"].
    static let montanaPeerLinkArrived = Notification.Name("montanaPeerLinkArrived")
    /// A coin's link was tapped: the tabs open the wallet (03.10).
    static let montanaOpenWallet = Notification.Name("montanaOpenWallet")
    /// The wallet's «Add account»: the tabs open the first screen as the drawer's plus does (03.10).
    static let montanaAddPerson = Notification.Name("montanaAddPerson")
}

/// The SSOT of entering a conversation from OUTSIDE live screens -- a notification tap and a
/// montana:// link. There is one road: the pendingOpenChat mark survives a cold start (screens are
/// not subscribed to the announcement yet), modals close from any page, the announcement goes after closing.
/// A second copy of this path already drifted: a link announced a conversation instantly and into
/// emptiness -- an introduction by link with the app closed gave birth to no chat, while a QR (a live
/// screen, subscribed listeners) did. There is no second copy of this exit any more.
enum MontanaOutsideOpen {
    /// The moment of the banner tap (system uptime) — the conversation's appearance measures
    /// itself against it and writes chat_open why=banner ms=…: the road from the finger to the
    /// open chat had no clock (the author's word 21.09: «too long», and the diary could not say how long).
    nonisolated(unsafe) static var tappedAt: TimeInterval? = nil
    nonisolated(unsafe) static var tappedFor: String = ""
    /// The same tap's clock handed to the feed: its first laid-out frame writes feed_first.
    nonisolated(unsafe) static var openedAt: TimeInterval? = nil
    /// THE GAME A BANNER OPENS (29.09): the chat opens by the one road below, and the conversation raises this game on its
    /// own stack as the invitation's tap does (MTChessPush) -- the invitee's entry accepts the invitation.
    nonisolated(unsafe) static var pendingGame: (chat: String, game: String)? = nil
    static func chat(_ ref: String) {
        UserDefaults.standard.set(ref, forKey: "pendingOpenChat")   // cold start: views not yet subscribed
        DispatchQueue.main.async {
            // Navigation works from ANY page: close all open modals/sheets
            // (QR, scanner, settings, profile), then open the chat the usual way.
            // NO WAITING BY A CLOCK (the author's word 21.09: «too long»): a fixed 0.45 s stood here
            // for the sheet's fall even when no sheet was up. The sheet's own completion says when
            // it is gone; with nothing to close the chat opens this very instant.
            let root = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }
                .first { $0.isKeyWindow }?
                .rootViewController
            let announce = {
                NotificationCenter.default.post(name: .openChatRequest, object: nil, userInfo: ["address": ref])
            }
            if let root, let standing = root.presentedViewController {
                MontanaP2PTrace.mark("outside_open", "sheet closes first")
                MTTop.dismiss(standing, kind: "outside-open", completion: announce)   // the one owner of the modal stack (25.09)
            } else {
                announce()
            }
        }
    }
}

/// THE WALLET RINGS NOTHING (the author's word 09.10.2026 16:00 MSK: «take everything else out, chats and calls among them»):
/// no PushKit registry and no CallKit provider -- the system never wakes this app for a call.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    static var launchedAt: TimeInterval = ProcessInfo.processInfo.systemUptime
    static var sceneSeen = false
    // Stage 8.3: the system relaunched us because background chunk uploads finished (or need
    // attention). Reconnect the session so the delegate receives the events; the delegate's
    // didFinishEvents then drains the letter queue — the manifest goes without the person.
    func application(_ application: UIApplication,
                     handleEventsForBackgroundURLSession identifier: String,   // SERVER-DEBT-ACK: OS relaunch hook for background blob uploads to the accelerator node (rung 4)
                     completionHandler: @escaping () -> Void) {
        MontanaP2PTrace.mark("blob_bgup", "relaunched for session events")
        MontanaBlobUpload.reconnect(completion: completionHandler)
    }

    // applicationDidBecomeActive / applicationWillResignActive are not written here: UIKit never calls them under the
    // scene lifecycle (the tree's own finding, 22.08 and 24.09). The application's return and departure are observed in
    // didFinishLaunching and handled below, one road each.

    /// THE APPLICATION'S RETURN TO THE PERSON, ONE ROAD (24.09, the noticed point 1). Everything that stood in
    /// applicationDidBecomeActive never ran on a return — the «online» word, the diary's tail, the invitation that waited
    /// for an identity, the day's card, the subscriptions, the undropped boxes, the orphan bodies — while comments across
    /// the tree said it did. They ride here. What the scene's phase already does on the same motion is not done twice:
    /// the extension's box and the node's box, the badge, the share grid (remirrorShareStore) and the node's start
    /// (onForeground); the telemetry's active mark has its own observers; the extension's old unread ledger is gone for
    /// good (the scene deletes it); and the live cards are not poured onto the node at every opening — a beacon of the
    /// owner's activity (stage 24b) — but kept up by term.
    /// A RETURN IS THE LAUNCH OR A COMING BACK FROM THE BACKGROUND (24.09, the second critic's pass): the application is
    /// «active» again after the notification shade, the control centre, a system sheet or Face ID, and the person never
    /// left — the subscriptions' keychain, the cards, the drops and the sweep ran at every pull of the shade. The word «I am
    /// here» is said at every activation (once per state: the shade costs nothing); the rest only after a leaving. The dead
    /// method's instant redial of the nodes does not ride here: it never ran in a build, and at every pull of the shade it
    /// would tear down live channels — the knock storm the wake door stands against (MontanaWakeDoor), which redials after
    /// a real sleep.
    private static var away = true   // the launch is the first return
    static func appBecameActive() {
        E2E.shared.appPresence(open: true)       // «I am here» to every correspondence — once per state
        guard away else { return }               // SILENT-OK: the shade, a sheet, Face ID — the person never left
        away = false
        MontanaTelemetry.carryExtensionLines()   // what the extensions wrote while the app slept rides the next ship
        MontanaDiagShip.shipNow()   // back with the person — last run's tail ships at once
        MontanaMeeting.replayPendingInvite()   // the link that waited for an identity opens by itself (F-8)
        DispatchQueue.global(qos: .utility).async { MontanaCard.keepLiveCardsUp() }   // the day's card turns on time, off the screen's thread
        MontanaWakePush.registerConvs()   // the door's standing map: only what changed leaves
        Task { await MontanaWakePush.flushPendingDrops() }   // the boxes a drop failed to empty are asked again
        MontanaBlobUpload.sweepOrphanBodies()   // orphan handoff bodies mute the cargo check; a newborn body is spared
    }
    /// THE APPLICATION LEAVES THE PERSON (24.09): the farewell, and the diary says what it holds before the sleep.
    static func appLeft() {
        away = true                           // the next activation is a return
        E2E.shared.appPresence(open: false)   // the farewell
        MontanaDiagShip.shipNow()   // leaving the person — say it now, another occasion may not come
    }
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        MontanaP2PTrace.mark("launch_begin")
        SeedScope.forgetRetired()   // the VPN's own values left with it (08.10.2026): an upgraded phone forgets them at the launch
        MontanaDiagConsent.apply()   // no yes to the diary: the extensions hold no diary id (5.1.1(ii), 08.10.2026)
        MTTopNet.noteFirstLaunch()   // whether an earlier build had published this device's top row (5.1.2(i), 08.10.2026)
        MTRowLetter.eventWords = { MTGroup.shared.eventWords($0) }   // a group's event row speaks the group's names (stage R)
        AppDelegate.launchedAt = ProcessInfo.processInfo.systemUptime
        MontanaTelemetry.shared.install()   // crashes/hangs/events → Montana/Diagnostics/telemetry.log
        // THE TOUCH DIARY STAYS ON OUR OWN PHONES (App Review 2.5.14, 08.10.2026: a record of a person's activity needs their
        // explicit consent): the Debug builds the Mac puts on the author's phones write every touch and every field's editing
        // (24.09); a build from TestFlight or the App Store writes none.
        #if DEBUG
        MTTouchDiary.start()
        #endif
        MTTop.watch()   // the owner of the modal stack names what stands at every return, lets a system sheet go when the app leaves (25.09)
        MTVideoTrace.sink = { MontanaTelemetry.shared.event($0) }   // the video conveyor is visible in the metric
        MontanaDiagShip.kick()   // stage 8-N: beta telemetry to the node, anonymous by construction
        MontanaP2PTrace.onFailure = { MontanaDiagShip.shipOnFailure() }   // an error does not wait the quarter hour
        E2EStore.witness()   // can this device keep an identity -- before the person creates one
        Self.ensureMontanaFolder()   // «Montana» folder in Files → «On My iPhone» (like Brave/Termius)
        UNUserNotificationCenter.current().delegate = self
        MontanaNotifyGate.registerCategories()   // the one registration ([C-1]); repeated when the lock-screen name switch flips
        // The system prompt is NOT raised here. Raised at launch it lands on a person who has not
        // yet seen a single screen of ours, and it lands beside the local-network prompt — two
        // system windows at once, neither explained. It is raised by MontanaNotifyGate, after the
        // person holds an identity and after the question of the direct link is settled.
        // The advertisement carries this device's writer tag so a sibling of the same seed is told apart
        // from this very device: their reference is identical, being derived from one seed.
        // Layer 1: secrets → AfterFirstUnlock (attribute rewrite). Layer 3: on unlock
        // of the device the storage opens — instantly repair the session/WS instead of a blind storm.
        E2EKeychain.migrateDeviceOnlyAccessibility()
        NotificationCenter.default.addObserver(
            forName: UIApplication.protectedDataDidBecomeAvailableNotification, object: nil, queue: .main) { _ in
            E2EKeychain.migrateDeviceOnlyAccessibility()
        }
        MontanaWakePush.bootstrap()   // rung 4: registering the APNs token on the accelerator server
        MontanaBackgroundRefresh.register()   // the system's own window (18.09): asked before launch ends, as it must be
        NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { _ in
            MontanaBackgroundRefresh.schedule()   // every leave asks for the next window
        }
        // THE APP'S OWN WORD RIDES THE APPLICATION'S LIFE (24.09, the author's word: «last seen differs from phone to
        // phone»). The greeting and the farewell stood in applicationDidBecomeActive / applicationWillResignActive, which
        // UIKit never calls under the scene lifecycle: in three days of the fleet's diaries (34 devices) not one phone said
        // «I am here» or «I left» — 502 app words, every one an echo — and every peer's «last seen» was the last chat word
        // it happened to hear, a different one on every phone. The application's notifications, not a window's phase: the
        // app declares several windows (an iPad), and one window leaving the screen is not the person leaving the app.
        // Every other duty of the return and the departure rides the same two roads (appBecameActive, appLeft).
        NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            AppDelegate.appBecameActive()
        }
        NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { _ in
            // Nothing of the application stands on the screen (the critic's pass: a window's word is never a farewell).
            if UIApplication.shared.applicationState == .background { AppDelegate.appLeft() }
        }
        MontanaWakePush.retireCalls()   // the call token an earlier build registered leaves the nodes, once
        MontanaP2PTrace.mark("launch_end")
        MTMusicFolders.lay()   // the lent folders' last list stands before any page asks (the author's word 24.09)
        MontanaEntropy.warm()   // the seed is gathered before anyone draws, and the diary names what it stands on
        // A copy the previous run did not finish is not a copy: it leaves before anybody can take it
        // for one. The cloud copy, when the person asked for one, is refreshed while the app is on
        // screen and not oftener than once a day (the critic, 23.09).
        MontanaArchive.onOwnQueue { MontanaBackup.sweep() }
        CopyInventory.tickSoon()   // after the feed is read: a plan that leaves something out needs the letters
        MontanaAppleID.publish()          // this device's seed reaches the Apple Account's keychain, when the switch stands (28.09)
        HomeNodeWatch.shared.tickSoon()   // the person's own node: the daily copy, when it is named and switched on (28.09)
        MTKeeping.shared.tickSoon()       // the copy kept by the people one writes to: the daily renewal, when the person chose it (08.10)
        return true
    }

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        MontanaWakePush.onDeviceToken(deviceToken)
    }
    // A background (silent) push of a service letter: open the envelope and hand it to the same receiving path.
    // The name and avatar refresh the mirrors BEFORE the next visible banner -- the banner will not show an old name.
    /// A WAKE IS A ROAD OUT AS WELL AS IN (18.09). A background launch by a push used to collect the
    /// mailbox and lay the incoming letter down, and stop: the outgoing queue's launch drain lives in
    /// the screen, and there is no screen in the background. Measured 17.09 14:24 on the tester's
    /// phone: woken by the peer's draft, the node open in four seconds, a text letter of the hour
    /// before still queued — it waited eighteen more hours for a hand. The wake proves the network
    /// is there: every loud letter knocks at once (the HTTPS knock needs no channel), then the rest
    /// of the queue takes its due turn. The forced drain marks its own throttle; the plain drain
    /// skips what the forced one has just tried.
    static func drainOutgoingOnWake(_ why: String) {
        MontanaP2PTrace.mark("wake_drain", "background launch by a push (\(why)) — the outgoing queue rides now")
        MontanaDeliveryEngine.shared.drainOnDoorAlive("push:" + why)
        MontanaDeliveryEngine.shared.drainAll()
    }
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        guard let envB64 = userInfo["env"] as? String, let sealed = Data(base64Encoded: envB64),
              let (conv, mid, text) = MontanaWakePush.openLetterEnvelope(sealed) else {
            // A silent ring without an envelope -- including the wake of an introduction first letter
            // (F-2): there is no envelope by construction (there is no pipe secret yet), the letter
            // waits on the node, and only a live channel can fetch it. Raising the core is the answer to the ring.
            MontanaWakeDoor.arrived("ring", at: userInfo["at"] as? Int)
            MontanaWakePush.drainInbox()
            // THE RING IS ANSWERED BY READING THE WHOLE BOX, WITHIN THE WAKE (21.09, the critic): the
            // node's own ringer sends exactly this envelope-less ring for every unconfirmed letter.
            Task { await MontanaWakePush.fetchBoxOnWake(); completionHandler(.newData) }
            return
        }
        MontanaP2PTrace.mark("wakepush_bg", "mid=\(String(mid.prefix(8)))")
        MontanaWakeDoor.arrived("letter", at: userInfo["at"] as? Int)
        MontanaTelemetry.carryExtensionLines()
        // Woke in the background for a letter -- and finished telling the journal at the same time.
        // Diagnostics does not ask for a waking of its own: the phone got up on business, and this is
        // the only case where it speaks without being opened by the person.
        MontanaDiagShip.shipNow()
        if text.hasPrefix(MontanaWakePush.letterBlobMark) {
            Task {   // a long link letter: pull the blob and lay down the full text
                // The one long-letter road lands it, keeps its hour or buries it — a ring asks no sooner
                // than the drain would (23.09). The reference is NEVER shown as a letter (07.09: a friend
                // saw «LB:{…}» in a bubble): a letter that waits, waits in the inbox, the same road as the drain.
                switch await MontanaWakePush.takeLongLetter(conv: conv, mid: mid, text: text) {
                case .landed(let full):
                    await MainActor.run {
                        NotificationCenter.default.post(name: .montanaP2PIncoming, object: nil,
                                                        userInfo: ["from": conv, "mid": mid, "text": full, "transport": "push"])
                    }
                case .waiting:
                    MontanaWakePush.stashLongLetter(conv: conv, mid: mid, text: text)
                case .buried:
                    break
                }
                await MontanaWakePush.fetchBoxOnWake()
                completionHandler(.newData)
            }
            return
        }
        NotificationCenter.default.post(name: .montanaP2PIncoming, object: nil,
                                        userInfo: ["from": conv, "mid": mid, "text": text, "transport": "push"])
        // THE WAKE READS THE WHOLE BOX, NOT ONLY THE LETTER IT CARRIED (21.09, the critic: the tablet
        // was awake nine seconds at 22:23 and read nothing; the photo boxed at 22:09 waited fifteen
        // hours). The completion follows the bounded read.
        Task { await MontanaWakePush.fetchBoxOnWake(); completionHandler(.newData) }
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        MontanaP2PTrace.mark("wakepush_register_fail", "err=\(error.localizedDescription)")
    }

    // Callback from the native iPhone «Recents»: iOS opens the app with INStartCall/Audio/VideoCallIntent,
    // the peer address is in personHandle.value (we put it there as CXHandle on a call).
    func application(_ application: UIApplication, continue userActivity: NSUserActivity,
                     restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
        // A WEB LINK OF OURS IS AN INVITATION, NEVER A CALL (23.09): every activity used to go to the call-intent
        // parser, which refused the camera's universal link in silence. The link goes to the one link entrance; an
        // activity nobody takes is named, so the next loss says what came.
        if userActivity.activityType == NSUserActivityTypeBrowsingWeb, let url = userActivity.webpageURL {
            MontanaMeeting.handleLink(url)
            return true
        }
        MontanaP2PTrace.mark("activity_in", "type=\(userActivity.activityType) taken=0")   // the wallet places no call from Recents
        return false
    }

    // The app's folder in «Files» → «On My iPhone» → Montana (app icon). iOS shows the Documents folder
    // with UIFileSharingEnabled + LSSupportsOpeningDocumentsInPlace, if it has content.
    static func ensureMontanaFolder() {
        guard let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let fm = FileManager.default
        // Clean the Documents root of service junk and old plaintext media —
        // only Montana/Chats/… (encrypted content) remains in the user folder.
        let junk = ["e2e.log", "seed-write-audit.txt", "About the Montana folder.txt"]
        if let items = try? fm.contentsOfDirectory(atPath: dir.path) {
            for it in items {
                let isJunk = junk.contains(it) || it.hasPrefix("voice_") || it.hasPrefix("att_") || it.hasPrefix("chatav_") || it.hasPrefix("cmp_")
                if isJunk { try? fm.removeItem(at: dir.appendingPathComponent(it)) }
            }
        }
        // Ensure the root folder exists (otherwise Files won't show the app folder until first message).
        MontanaArchive.migrateToEnglishPaths()   // one-time ru→en rename of legacy folders
        try? fm.createDirectory(at: dir.appendingPathComponent(MontanaPaths.root).appendingPathComponent(MontanaPaths.chats), withIntermediateDirectories: true)
        MontanaArchive.ensureLocalizedFolderNames()   // Files app shows folder names in the device language
    }

    // banner, even when the app is open
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let ud = UserDefaults.standard
        guard ud.object(forKey: "notifEnabled") as? Bool ?? true else { completionHandler([]); return }
        if MTPlayQuiet.held {   // a game stands on the screen: no banner at all (03.10)
            MontanaP2PTrace.mark("notify_judge", mid: nil, "why=play")
            completionHandler([]); return
        }
        // The ONLY place deciding «whether to show» in the foreground: chat open/muted -> silent.
        MontanaWakePush.drainInbox()   // a letter from a push goes into the chat at once, the app is open
        MontanaWakePush.fetchBoxKick()   // and with it everything waiting in the node mailbox
        MontanaKeychain.set("nseUnread", Data())   // the critic: a live app sees for itself -- the NSE count
        E2E.shared.recalcBadge()                    // goes to zero, the badge does not stick with the window open
        let info = notification.request.content.userInfo
        let chat = (info["chat"] as? String) ?? ""
        // THE JUDGE SPEAKS EVERY VERDICT (21.09, the critic): its silences left no line, and a
        // «second banner» could not be told from «composed, never shown» in the diary.
        let jm = (info["mid"] as? String) ?? ""
        // A GAME'S WORD IS JUDGED BY ITS BOARD (29.09): the end of a game has no bubble in the chat, so the open chat does
        // not read it; the board on the screen does (MTChessGameScreen.shownGame).
        let game = (info["game"] as? String) ?? ""
        if !game.isEmpty, game == MTChessGameScreen.shownGame {
            MontanaP2PTrace.mark("notify_judge", mid: jm.isEmpty ? nil : jm, "why=game-open")
            completionHandler([]); return
        }
        let gameEnd = (info["game_end"] as? Int) == 1
        if !chat.isEmpty, !gameEnd, chat == ChatStore.openConvNow {
            E2E.shared.recalcBadge()   // revert the NSE increment: an open chat is read by definition
            MontanaP2PTrace.mark("notify_judge", mid: jm.isEmpty ? nil : jm, "why=chat-open")
            completionHandler([]); return
        }
        // A MUTED OR ARCHIVED CHAT SAYS NOTHING (MTQuietChats, the author's words 03.10 21:48): the defaults this read held no mute
        // since the store keeps it in the vault and the keychain, so a muted chat's banner showed over the open app.
        if MTQuietChats.holds(chat) {
            MontanaP2PTrace.mark("notify_judge", mid: jm.isEmpty ? nil : jm, "why=quiet")
            completionHandler([]); return
        }
        // The wire beat the push: the row already stands in the chat and the app's own door
        // rang (or rings) for it — a second, system banner for the same letter is the double
        // the author forbids (23.08: «two notifications, one video»).
        if !chat.isEmpty, let mid = info["mid"] as? String, !mid.isEmpty,
           MontanaDeliveryEngine.shared.store?.messages[chat]?.contains(where: { $0.msgId == "mid:" + mid }) == true {
            MontanaP2PTrace.mark("notify_skip", mid: mid, "why=row-already-in-chat (foreground)")
            completionHandler([.badge]); return
        }
        var opts: UNNotificationPresentationOptions = [.banner, .badge]
        if ud.object(forKey: "notifSound") as? Bool ?? true { opts.insert(.sound) }
        MontanaP2PTrace.mark("notify_judge", mid: jm.isEmpty ? nil : jm, "why=shown chat=\(chat.isEmpty ? "-" : String(chat.prefix(10)))")
        completionHandler(opts)
    }

    // a tap on the notification: the wallet's banners carry no answer (one category, no action)
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        MontanaOutsideOpen.tappedAt = ProcessInfo.processInfo.systemUptime
        MontanaOutsideOpen.tappedFor = (info["chat"] as? String) ?? (info["from"] as? String) ?? ""
        MontanaP2PTrace.mark("notif_tap", mid: (info["mid"] as? String).flatMap { $0.isEmpty ? nil : $0 },
                             "chat=\(String(MontanaOutsideOpen.tappedFor.prefix(10))) action=\(response.actionIdentifier == UNNotificationDefaultActionIdentifier ? "open" : response.actionIdentifier) "
                             + "since_launch_ms=\(Int((ProcessInfo.processInfo.systemUptime - AppDelegate.launchedAt) * 1000))")
        // A LETTER TO A PERSON ON THE SHELF (07.10, MTShelfPost): the tap seats that person; their letters wait in their own inbox
        // and land at the lift.
        if let seat = info["seat"] as? String, !seat.isEmpty {
            DispatchQueue.main.async { MTSeats.shared.switchTo(seat) }
            completionHandler()
            return
        }
        MontanaWakePush.drainInbox()   // a banner tap: the letter is in the chat before it opens
        MontanaWakePush.fetchBoxKick()   // and everything waiting in the node mailbox, by the same movement
        let chat = (info["chat"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? (info["from"] as? String) ?? ""
        if let game = info["game"] as? String, !game.isEmpty, !chat.isEmpty { MontanaOutsideOpen.pendingGame = (chat, game) }
        if !chat.isEmpty { MontanaOutsideOpen.chat(chat) }
        completionHandler()
    }
}

// Notifications are raised by this device, from a message it already holds.
enum MontanaLocalNotify {
    // The answer of the system is handed back: a switch that stays on while the phone says no
    // is a promise the device never made.
    static func requestPermission(_ done: ((Bool) -> Void)? = nil) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, err in
            if let err { NSLog("[notify] authorization refused: \(err.localizedDescription)") }
            DispatchQueue.main.async { done?(granted) }
        }
    }
}
// ═══════════════════════════════════════════════════════════════════
// TELEMETRY: crashes (signals + NSException, native backtrace),
// hangs (main-thread watchdog), sequence event log.
// Writes to Documents/Montana/Diagnostics/telemetry.log — visible in Files
// and is pulled from any phone: devicectl copy from appDataContainer.
// ═══════════════════════════════════════════════════════════════════
private var gMontanaCrashFD: Int32 = -1
/// THE DYING RUN'S OWN WORD (23.09): «signal-11», «exception-NSGenericException». The next launch read
/// the journal's verdict as «unexplained» while the exception stood one line above it; the run that
/// falls now writes what felled it into run.crashed, and the judge reads that fact first.
private var gMontanaCrashMarkFD: Int32 = -1
private var gMontanaCrashMarked = false   // the exception spoke first; the abort's signal adds no second word
/// The handler's scratch, taken once at install: a signal handler may not allocate -- the crash can
/// stand inside the allocator, holding its lock -- and the Swift arrays it used to build did allocate.
private var gMontanaCrashText: UnsafeMutablePointer<CChar>? = nil
private var gMontanaCrashFrames: UnsafeMutablePointer<UnsafeMutableRawPointer?>? = nil

/// `v` in `width` decimal digits, zero-padded -- arithmetic only (async-signal-safe).
private func montanaCrashField(_ v: Int, _ width: Int, _ to: UnsafeMutablePointer<CChar>) {
    var v = v, i = width - 1
    while i != -1 { to[i] = CChar(48 + v % 10); v /= 10; i -= 1 }
}

/// `v` in as many decimal digits as it has; returns their count (async-signal-safe).
private func montanaCrashDigits(_ v: Int, _ to: UnsafeMutablePointer<CChar>) -> Int {
    var w = 1, x = v
    while x >= 10 { x /= 10; w += 1 }
    montanaCrashField(v, w, to)
    return w
}

private func montanaCrashCopy(_ s: StaticString, _ to: UnsafeMutablePointer<CChar>) -> Int {
    memcpy(to, s.utf8Start, s.utf8CodeUnitCount)
    return s.utf8CodeUnitCount
}

/// «\n2026-09-23T10:30:22.123Z» -- the journal's own stamp (MontanaLog.stamp), made from the wall
/// clock by the civil-date arithmetic of days since 1970 (Hinnant): no formatter, no allocation.
private func montanaCrashStamp(_ to: UnsafeMutablePointer<CChar>) -> Int {
    var ts = timespec()
    clock_gettime(CLOCK_REALTIME, &ts)
    let secs = Int(ts.tv_sec), ms = Int(ts.tv_nsec) / 1_000_000
    let rem = secs % 86_400
    let z = secs / 86_400 + 719_468
    let era = z / 146_097
    let doe = z - era * 146_097
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
    let mp = (5 * doy + 2) / 153
    let day = doy - (153 * mp + 2) / 5 + 1
    let month = mp < 10 ? mp + 3 : mp - 9
    let year = yoe + era * 400 + (month <= 2 ? 1 : 0)
    to[0] = 10
    montanaCrashField(year, 4, to + 1); to[5] = 45
    montanaCrashField(month, 2, to + 6); to[8] = 45
    montanaCrashField(day, 2, to + 9); to[11] = 84
    montanaCrashField(rem / 3600, 2, to + 12); to[14] = 58
    montanaCrashField(rem % 3600 / 60, 2, to + 15); to[17] = 58
    montanaCrashField(rem % 60, 2, to + 18); to[20] = 46
    montanaCrashField(ms, 3, to + 21); to[24] = 90
    return 25
}

/// `v` as «0x» and its hexadecimal digits; returns their count (async-signal-safe).
private func montanaCrashHex(_ v: UInt, _ to: UnsafeMutablePointer<CChar>) -> Int {
    to[0] = 48; to[1] = 120
    var w = 1, x = v
    while x >= 16 { x >>= 4; w += 1 }
    var i = w - 1, y = v
    while i != -1 { let d = Int(y & 15); to[2 + i] = CChar(d < 10 ? 48 + d : 87 + d); y >>= 4; i -= 1 }
    return 2 + w
}

/// THE STACK THE HANDLER STANDS ON (the author's word 03.10.2026 13:33 MSK: «find the root of the crashes at 01:18 and 13:18»).
/// T1 2069 fell eleven times with SIGSEGV, KERN_PROTECTION_FAILURE (MetricKit: type 1, code 2), and not one of those deaths
/// left the handler's line or its mark in run.crashed: the handler was installed by signal() and ran on the thread's own
/// stack, and a thread that dies of an exhausted stack has no room left to run it -- the kernel kills the process in
/// silence. The system's report gave no frame either, and the phone keeps no new report once 25 lie on it. The handler
/// now runs on a stack of its own (sigaltstack, SA_ONSTACK) and reads the fallen thread from the signal's context: the
/// fault's address, the thread's stack bounds and verdict (overflow=1 when the fault or the stack pointer stands at the
/// guard below the stack), and its frames as raw addresses with the image base, for atos against the build's dSYM.
private var gMontanaAltStack: UnsafeMutableRawPointer? = nil
private let gMontanaAltStackSize = 128 * 1024
/// The base of the image that holds our code (Montana, or Montana.debug.dylib in a Debug build), read once at install.
private var gMontanaImageBase: UInt = 0
/// THE IMAGES THE STACK IS COUNTED BY (03.10, T1 2070 15:11 and 15:13 MSK): the handler wrote the fallen thread's 96 innermost
/// frames, and the megabyte was spent below them, where nothing was written. Every frame of the chain is given to the image
/// its return stands in -- ours first, «other» last -- by the text ranges read once at install.
private let gMontanaImageNames: [StaticString] = ["Montana", "SwiftUI", "SwiftUICore", "AttributeGraph", "UIKitCore",
                                                  "libswiftCore.dylib", "QuartzCore", "CoreFoundation", "Foundation", "other"]
private var gMontanaImageLow: UnsafeMutablePointer<UInt>? = nil
private var gMontanaImageHigh: UnsafeMutablePointer<UInt>? = nil
private var gMontanaImageFrames: UnsafeMutablePointer<Int>? = nil
private var gMontanaImageBytes: UnsafeMutablePointer<Int>? = nil
private var gMontanaOuterFrames: UnsafeMutablePointer<UInt>? = nil
private let gMontanaOuterCount = 48

/// The text ranges of the counted images; ours is the image this code lives in, whatever its file is called.
private func montanaCountImages() {
    let k = gMontanaImageNames.count
    let low = UnsafeMutablePointer<UInt>.allocate(capacity: k), high = UnsafeMutablePointer<UInt>.allocate(capacity: k)
    low.initialize(repeating: 0, count: k); high.initialize(repeating: 0, count: k)
    func text(_ h: UnsafePointer<mach_header>) -> (UInt, UInt)? {
        var size: UInt = 0
        guard let t = h.withMemoryRebound(to: mach_header_64.self, capacity: 1, { getsegmentdata($0, "__TEXT", &size) }) else { return nil }
        return (UInt(bitPattern: t), UInt(bitPattern: t) &+ size)
    }
    if let ours = UnsafePointer<mach_header>(bitPattern: gMontanaImageBase), let r = text(ours) { low[0] = r.0; high[0] = r.1 }
    let names = gMontanaImageNames.map { $0.description }
    for i in 0..<_dyld_image_count() {
        guard let h = _dyld_get_image_header(i), let c = _dyld_get_image_name(i) else { continue }
        let name = String(cString: c).split(separator: "/").last.map(String.init) ?? ""
        guard let j = names.firstIndex(of: name), j != 0, j != k - 1, let r = text(h) else { continue }
        low[j] = r.0; high[j] = r.1
    }
    gMontanaImageLow = low; gMontanaImageHigh = high
    gMontanaImageFrames = .allocate(capacity: k); gMontanaImageBytes = .allocate(capacity: k)
    gMontanaOuterFrames = .allocate(capacity: gMontanaOuterCount)
}

/// The counted image a return stands in, or the last («other»); arithmetic only (async-signal-safe).
private func montanaImageIndex(_ pc: UInt) -> Int {
    let last = gMontanaImageNames.count - 1
    guard let low = gMontanaImageLow, let high = gMontanaImageHigh else { return last }
    var j = 0
    while j != last {
        if pc >= low[j], pc < high[j] { return j }
        j += 1
    }
    return last
}

private func montanaSignalAction(_ sig: Int32, _ info: UnsafeMutablePointer<__siginfo>?, _ uap: UnsafeMutableRawPointer?) {
    if gMontanaCrashFD >= 0, let buf = gMontanaCrashText, let frames = gMontanaCrashFrames {
        // THE RECORD WEARS THE JOURNAL'S TIME (23.09): the 13:30:22 crash on the iPhone 15 stood without
        // one, and every filter by the hour walked past it.
        var n = montanaCrashStamp(buf)
        n += montanaCrashCopy(" === CRASH signal ", buf + n)
        n += montanaCrashDigits(Int(sig), buf + n)
        _ = write(gMontanaCrashFD, buf, n)
        let fault = UInt(bitPattern: info?.pointee.si_addr)
        let me = pthread_self()
        let high = UInt(bitPattern: pthread_get_stackaddr_np(me))
        let low = high &- UInt(pthread_get_stacksize_np(me))
        var pc: UInt = 0, lr: UInt = 0, fp: UInt = 0, sp: UInt = 0
        #if arch(arm64)
        if let uc = uap?.assumingMemoryBound(to: ucontext_t.self), let mc = uc.pointee.uc_mcontext {
            pc = UInt(mc.pointee.__ss.__pc); lr = UInt(mc.pointee.__ss.__lr)
            fp = UInt(mc.pointee.__ss.__fp); sp = UInt(mc.pointee.__ss.__sp)
        }
        #endif
        // The guard page lies just below the stack's low end: a fault there, or a stack pointer at the low end, is an
        // exhausted stack.
        let overflow = (fault &+ 65_536 >= low && fault < low &+ 16_384) || (sp != 0 && sp < low &+ 16_384)
        n = montanaCrashCopy(" fault=", buf); n += montanaCrashHex(fault, buf + n)
        n += montanaCrashCopy(" sp=", buf + n); n += montanaCrashHex(sp, buf + n)
        _ = write(gMontanaCrashFD, buf, n)
        n = montanaCrashCopy(" stack=", buf); n += montanaCrashHex(low, buf + n)
        n += montanaCrashCopy("-", buf + n); n += montanaCrashHex(high, buf + n)
        n += montanaCrashCopy(overflow ? " overflow=1" : " overflow=0", buf + n)
        n += montanaCrashCopy(" main=", buf + n); n += montanaCrashDigits(pthread_main_np() != 0 ? 1 : 0, buf + n)
        _ = write(gMontanaCrashFD, buf, n)
        n = montanaCrashCopy(" base=", buf); n += montanaCrashHex(gMontanaImageBase, buf + n)
        n += montanaCrashCopy(" frames:", buf + n)
        _ = write(gMontanaCrashFD, buf, n)
        // The fallen thread's own frames, read from its context -- the pc, the link register, then the frame chain while
        // it stays inside the thread's stack (reading only: a full stack is still readable).
        let mask: UInt = 0x0000_007F_FFFF_FFFF   // without the pointer-authentication bits
        var count = 0, f = fp
        // Nothing is allocated here: every frame goes out through the same scratch, one write each.
        if pc != 0 {
            var k = montanaCrashCopy(" ", buf); k += montanaCrashHex(pc & mask, buf + k)
            _ = write(gMontanaCrashFD, buf, k); count += 1
        }
        if lr != 0 {
            var k = montanaCrashCopy(" ", buf); k += montanaCrashHex(lr & mask, buf + k)
            _ = write(gMontanaCrashFD, buf, k); count += 1
        }
        while count < 96, f >= low, f &+ 16 <= high, f % 8 == 0, let p = UnsafePointer<UInt>(bitPattern: f) {
            let next = p[0], ret = p[1]
            if ret == 0 { break }
            var k = montanaCrashCopy(" ", buf); k += montanaCrashHex(ret & mask, buf + k)
            _ = write(gMontanaCrashFD, buf, k); count += 1
            if next <= f { break }
            f = next
        }
        n = montanaCrashCopy(" ===\n", buf)
        _ = write(gMontanaCrashFD, buf, n)
        // THE WHOLE CHAIN, COUNTED BY IMAGE (03.10): the frames above are the innermost; the chain is walked once more to its
        // end, each frame's room (the distance to its caller's record) given to the image its return stands in, and the
        // outermost frames close the line -- where the room went, and from where the road began.
        if let cf = gMontanaImageFrames, let cb = gMontanaImageBytes, let outer = gMontanaOuterFrames {
            let k = gMontanaImageNames.count
            var j = 0
            while j != k { cf[j] = 0; cb[j] = 0; j += 1 }
            var walked = 0, g = fp
            while g >= low, g &+ 16 <= high, g % 8 == 0, let p = UnsafePointer<UInt>(bitPattern: g) {
                let next = p[0], ret = p[1] & mask
                if ret == 0 || next <= g { break }
                let i = montanaImageIndex(ret)
                cf[i] += 1; cb[i] += Int(next &- g)
                outer[walked % gMontanaOuterCount] = ret
                walked += 1
                g = next
            }
            n = montanaCrashCopy("=== STACK frames=", buf); n += montanaCrashDigits(walked, buf + n)
            n += montanaCrashCopy(" kb=", buf + n); n += montanaCrashDigits(Int((high &- (sp != 0 ? sp : fault)) / 1024), buf + n)
            _ = write(gMontanaCrashFD, buf, n)
            j = 0
            while j != k {
                if cf[j] != 0 {
                    n = montanaCrashCopy(" ", buf); n += montanaCrashCopy(gMontanaImageNames[j], buf + n)
                    n += montanaCrashCopy("=", buf + n); n += montanaCrashDigits(cf[j], buf + n)
                    n += montanaCrashCopy("/", buf + n); n += montanaCrashDigits(cb[j] / 1024, buf + n)
                    n += montanaCrashCopy("kb", buf + n)
                    _ = write(gMontanaCrashFD, buf, n)
                }
                j += 1
            }
            n = montanaCrashCopy(" outer:", buf)
            _ = write(gMontanaCrashFD, buf, n)
            var o = walked > gMontanaOuterCount ? walked - gMontanaOuterCount : 0
            while o != walked {
                n = montanaCrashCopy(" ", buf); n += montanaCrashHex(outer[o % gMontanaOuterCount], buf + n)
                _ = write(gMontanaCrashFD, buf, n)
                o += 1
            }
            n = montanaCrashCopy(" ===\n", buf)
            _ = write(gMontanaCrashFD, buf, n)
        }
        // The handler's own stack too, as before (on the side stack it shows the handler's road, nothing more).
        let depth = backtrace(frames, 64)
        backtrace_symbols_fd(frames, depth, gMontanaCrashFD)
        fsync(gMontanaCrashFD)
        if gMontanaCrashMarkFD >= 0, !gMontanaCrashMarked {
            var m = montanaCrashCopy("signal-", buf)
            m += montanaCrashDigits(Int(sig), buf + m)
            if overflow { m += montanaCrashCopy("-stack-overflow", buf + m) }
            _ = write(gMontanaCrashMarkFD, buf, m)
            fsync(gMontanaCrashMarkFD)
        }
    }
    signal(sig, SIG_DFL); raise(sig)
}

/// The handler on its own stack: the side stack for the calling thread (the main thread, at launch), then every
/// fatal signal through sigaction with SA_ONSTACK and SA_SIGINFO.
private func montanaInstallSignalHandlers() {
    if gMontanaAltStack == nil {
        let mem = UnsafeMutableRawPointer.allocate(byteCount: gMontanaAltStackSize, alignment: 16)
        var ss = stack_t(ss_sp: mem, ss_size: gMontanaAltStackSize, ss_flags: 0)
        if sigaltstack(&ss, nil) == 0 { gMontanaAltStack = mem } else { mem.deallocate() }
    }
    gMontanaImageBase = UInt(bitPattern: #dsohandle)   // the mach header of the image this code lives in
    montanaCountImages()
    for sig in [SIGABRT, SIGSEGV, SIGILL, SIGTRAP, SIGBUS, SIGFPE] {
        var sa = sigaction()
        sa.__sigaction_u.__sa_sigaction = montanaSignalAction
        sa.sa_flags = SA_SIGINFO | SA_ONSTACK
        sigemptyset(&sa.sa_mask)
        sigaction(sig, &sa, nil)
    }
}

/// The image that holds our code and its base, for the journal: the crash line's raw frames minus this base are the
/// offsets atos reads against the build's dSYM.
private func montanaImageLine() -> String {
    var info = dl_info()
    guard dladdr(#dsohandle, &info) != 0, let base = info.dli_fbase else { return "IMAGE unknown" }   // NOT-UI: the journal's own line
    let name = info.dli_fname.map { String(cString: $0).split(separator: "/").last.map(String.init) ?? "?" } ?? "?"
    return "IMAGE \(name) base=0x" + String(UInt(bitPattern: base), radix: 16) + " altstack=\(gMontanaAltStack != nil ? 1 : 0)"
}

/// One line for every change of the network path. The airplane-mode tests stand on the claim
/// «there was no network for the entire run», and a claim about an entire run needs a witness that
/// watched the entire run — a snapshot at launch would miss a path that came up in the middle.
enum MontanaNetWitness {
    private static let monitor = NWPathMonitor()
    private static var started = false
    private static var netSig = ""
    private static var netSigSeen = false
    private static var rejudgeDue = false   // the signature changed; the doors are re-judged on the first path that carries

    /// Whether ANY tunnel stands on this device — a third-party VPN client's (this app carries none since 08.10.2026).
    /// The system scopes its proxy settings per interface; a scoped entry named utun/ipsec/ppp
    /// is a standing tunnel. Only the FACT leaves the device — never a name, never an address.
    static func tunnelPresent() -> Bool {
        guard let dict = CFNetworkCopySystemProxySettings()?.takeRetainedValue() as? [String: Any],
              let scoped = dict["__SCOPED__"] as? [String: Any] else { return false }
        return scoped.keys.contains { k in
            k.hasPrefix("utun") || k.hasPrefix("ipsec") || k.hasPrefix("ppp") || k.hasPrefix("tap")
        }
    }

    /// THE ROAD ABOVE A TUNNEL (the author's word 03.10.2026 16:41 MSK: «make our P2P nodes stand above the VPN tunnel, and if
    /// that cannot be, put out the dead VPN nodes that keep our nodes away -- so Montana always works»). Margarita's phone, 03.10
    /// 12:48-16:20 MSK on 2063: a third-party tunnel stood, ours was off, every door of the nodes died through it, and her call at
    /// 16:20:14 fell into that window; the doors answered 0.7 s after the tunnel left. A socket bound to a physical interface
    /// leaves any tunnel that does not hold every route -- ours does not, nor do most. This is the interface a door is bound to
    /// while a tunnel stands (MontanaP2PDirect.doorRoadAbove).
    private static let physicalLock = NSLock()
    private static var physicalNow: NWInterface? = nil
    static var physical: NWInterface? { physicalLock.lock(); defer { physicalLock.unlock() }; return physicalNow }

    static func start() {
        guard !started else { return }
        started = true
        monitor.pathUpdateHandler = { p in
            let phys = p.availableInterfaces.first { $0.type == .wifi || $0.type == .cellular || $0.type == .wiredEthernet }
            physicalLock.lock(); physicalNow = phys; physicalLock.unlock()
            // 16.6.19 — the door verdicts are per network: when the interface set or the tunnel
            // fact changes, every door is judged afresh (a web door dead on cellular is the only
            // road under a full tunnel). Not on every re-evaluation — a flapping tunnel re-evals
            // several times a second — only on a real change of the signature.
            let sig = p.availableInterfaces.map { String(describing: $0.type) }.joined(separator: ",") + "|vpn=\(tunnelPresent() ? 1 : 0)"
            // ONE owner of «the network changed» ([C-1]): the door verdicts (16.6.19) and the signal
            // lanes to the store (15.4) both hang on this signature — the interface set and the
            // tunnel fact — and nowhere else.
            if sig != Self.netSig {
                Self.netSig = sig
                MontanaP2PDirect.resetDoorRoads()   // a new network or a new tunnel: every door is dialled above it again
                if Self.netSigSeen { Self.rejudgeDue = true }
                Self.netSigSeen = true
            }
            // THE NEW NETWORK IS KNOCKED WHEN IT CARRIES (29.09). The signature changes before the path is satisfied —
            // the tunnel's interface appears, its route a moment later — and every door knocked at the first change met
            // «Network is down» and was knocked again at the second, 27 ms on (T1 23:31:45.181Z and .208Z, 1988): two
            // volleys of dials into a tunnel with no route yet, and the engine at 912 goroutines. One re-judgement, on the
            // first satisfied path after the change; a path that never satisfies (the plane) re-judges nothing.
            if Self.rejudgeDue, p.status == .satisfied {
                Self.rejudgeDue = false
                MontanaNodes.onNetworkChanged(); MontanaWakePush.networkPathChanged(sig)
            }
            // The whole network environment in one line, every field a fact and none a person:
            // which interface kinds exist, whether v4/v6 ride, whether the path is metered or
            // constrained, and whether ANY tunnel stands. This is the line that says "there is
            // an obstacle on the road" before any letter has to prove it the hard way.
            let ifs = p.availableInterfaces.map { String(describing: $0.type) }.joined(separator: ",")
            // D-5: the path observer fires on every re-evaluation, and iOS re-evaluates a
            // tunnelled path several times a second — 97 identical lines in nine minutes, twice
            // within the same millisecond. The environment is a STATE: it speaks when it changes,
            // and once a quarter-hour to prove it is still being watched.
            MontanaP2PTrace.markChanged("net_env",
                "status=\(p.status) ifs=\(ifs.isEmpty ? "-" : ifs)"
                + " v4=\(p.supportsIPv4 ? 1 : 0) v6=\(p.supportsIPv6 ? 1 : 0) dns=\(p.supportsDNS ? 1 : 0)"
                + " metered=\(p.isExpensive ? 1 : 0) constrained=\(p.isConstrained ? 1 : 0)"
                + " vpn=\(tunnelPresent() ? 1 : 0)", every: 900)
        }
        monitor.start(queue: DispatchQueue(label: "montana.net.witness", qos: .utility))
    }
}

/// THE SYSTEM'S OWN VERDICT ON A DEATH (the author's word 05.09: «T1 folded by itself and the
/// diary says nothing»). The in-process handler sees signals and exceptions; it cannot see a
/// watchdog kill, a memory kill or a kill before the first line. The system keeps those and hands
/// them to the app at its next launch — written here into the same journal.
final class MontanaMetricSink: NSObject, MXMetricManagerSubscriber {
    static let shared = MontanaMetricSink()
    /// The system's whole report, beside the journal (Diagnostics/metrickit-<kind>-<seconds>.json, up to 1 MB), so a
    /// report whose stack the line could not read is still read whole off the phone. The file's name, for the line.
    static func keep(_ json: Data, kind: String) -> String {
        let dir = MontanaLog.url(.telemetry).deletingLastPathComponent()
        let name = "metrickit-\(kind)-\(Int(Date().timeIntervalSince1970)).json"
        try? json.prefix(1_048_576).write(to: dir.appendingPathComponent(name), options: .atomic)
        return name
    }
    /// THE SYSTEM'S DAILY BILL (the author's word 10.09): processor time, foreground and background
    /// time, cellular and Wi-Fi bytes — the day's cost of the app as the system counted it.
    func didReceive(_ payloads: [MXMetricPayload]) {
        for p in payloads {
            let cpu = p.cpuMetrics.map { Int($0.cumulativeCPUTime.converted(to: .seconds).value) } ?? -1
            let fg = p.applicationTimeMetrics.map { Int($0.cumulativeForegroundTime.converted(to: .seconds).value) } ?? -1
            let bg = p.applicationTimeMetrics.map { Int($0.cumulativeBackgroundTime.converted(to: .seconds).value) } ?? -1
            let cell = p.networkTransferMetrics.map { Int(($0.cumulativeCellularDownload + $0.cumulativeCellularUpload).converted(to: .megabytes).value) } ?? -1
            let wifi = p.networkTransferMetrics.map { Int(($0.cumulativeWifiDownload + $0.cumulativeWifiUpload).converted(to: .megabytes).value) } ?? -1
            let gpu = p.gpuMetrics.map { Int($0.cumulativeGPUTime.converted(to: .seconds).value) } ?? -1
            // THE DAY'S EXITS BY THE SYSTEM'S OWN WORDS (25.09): a tester's run ended two seconds after a call with
            // cause=unexplained -- the judge names only what the sentinel saw; the system counts every end by its
            // reason, and the count comes with the day's bill.
            var exits = ""
            if let e = p.applicationExitMetrics {
                let f = e.foregroundExitData, b = e.backgroundExitData
                exits = " fg_exits=normal:\(f.cumulativeNormalAppExitCount),memory:\(f.cumulativeMemoryResourceLimitExitCount),badaccess:\(f.cumulativeBadAccessExitCount),abnormal:\(f.cumulativeAbnormalExitCount),illegal:\(f.cumulativeIllegalInstructionExitCount),watchdog:\(f.cumulativeAppWatchdogExitCount)"
                    + " bg_exits=normal:\(b.cumulativeNormalAppExitCount),memory:\(b.cumulativeMemoryResourceLimitExitCount),pressure:\(b.cumulativeMemoryPressureExitCount),cpu:\(b.cumulativeCPUResourceLimitExitCount),badaccess:\(b.cumulativeBadAccessExitCount),abnormal:\(b.cumulativeAbnormalExitCount),illegal:\(b.cumulativeIllegalInstructionExitCount),watchdog:\(b.cumulativeAppWatchdogExitCount),lockedfile:\(b.cumulativeSuspendedWithLockedFileExitCount),bgtask:\(b.cumulativeBackgroundTaskAssertionTimeoutExitCount)"
            }
            let line = "cpu_s=\(cpu) gpu_s=\(gpu) fg_s=\(fg) bg_s=\(bg) cell_mb=\(cell) wifi_mb=\(wifi)" + exits
            MontanaLog.event("METRICKIT DAY " + line)
            MontanaP2PTrace.mark("metrickit_day", line)
        }
    }
    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for p in payloads {
            for c in p.crashDiagnostics ?? [] {
                // THE SYSTEM'S CRASH REPORT KEEPS ITS STACK AND ITS WORDS (23.09): only the signal and the
                // termination reason were kept -- the crashed thread's frames and the exception's own
                // message, which name the line that fell, were thrown away while a hang's frames were written.
                let ex = c.exceptionReason
                let words = ex.map { "\($0.exceptionName): \($0.composedMessage)" } ?? "-"
                var frames = MTMainStack.frames(ofReport: c.callStackTree.jsonRepresentation())
                // A REPORT WITH NO FRAME KEEPS ITS WHOLE TREE (03.10, T1 2069: eleven SIGSEGV reports, every one «frames:»
                // and nothing after it): the line names the threads the tree holds and the file the whole report went to.
                if frames.isEmpty || frames == "-" {
                    frames = MTMainStack.threadsLine(ofReport: c.callStackTree.jsonRepresentation()) + " raw=" + MontanaMetricSink.keep(c.jsonRepresentation(), kind: "crash")
                }
                MontanaLog.event("METRICKIT CRASH build=\(c.metaData.applicationBuildVersion) type=\(c.exceptionType?.stringValue ?? "-") code=\(c.exceptionCode?.stringValue ?? "-") signal=\(c.signal?.stringValue ?? "-") reason=\((c.terminationReason ?? "-").prefix(120)) exception=\(words.prefix(240)) frames: " + frames)
                MontanaP2PTrace.mark("metrickit_crash", "build=\(c.metaData.applicationBuildVersion) signal=\(c.signal?.stringValue ?? "-") reason=\(String((c.terminationReason ?? "-").prefix(60))) exception=\(String((ex?.exceptionName ?? "-").prefix(60)))")
            }
            for h in p.hangDiagnostics ?? [] {
                MontanaLog.event("METRICKIT HANG build=\(h.metaData.applicationBuildVersion) dur=\(h.hangDuration.value)s frames: " + MTMainStack.frames(ofReport: h.callStackTree.jsonRepresentation()))
                MontanaP2PTrace.mark("metrickit_hang", "build=\(h.metaData.applicationBuildVersion) dur=\(Int(h.hangDuration.value))s")
            }
        }
    }
}

/// THE MAIN THREAD'S STACK, TAKEN FROM OUTSIDE (the author's word 11.09: «the app froze on the
/// Calls tab — find it and close it»): the watchdog knew the main thread stood for 4.8 s and the
/// run was then killed, and no diary named a frame — the transport trace had rotated, the system's
/// report carries no stack in our line. So the watchdog now suspends the main thread for a moment,
/// reads its registers, walks the frame chain and writes the frames as image+offset (symbolicated
/// with the build's dSYM) with the nearest symbol where the table has one. Nothing is allocated
/// while the thread is held (it may hold the allocator's lock); names are made after the resume.
enum MTMainStack {
    private static var port: mach_port_t = 0
    private static var stackTop: UInt = 0, stackBottom: UInt = 0
    /// On the main thread, once.
    static func remember() {
        let t = pthread_self()
        port = pthread_mach_thread_np(t)
        stackTop = UInt(bitPattern: pthread_get_stackaddr_np(t))
        stackBottom = stackTop &- UInt(pthread_get_stacksize_np(t))
    }
    /// THE ROOM USED ON THE MAIN THREAD'S STACK, READ WHERE IT RAN OUT (03.10, T1 2069 and 2070: the first chat opened after a
    /// launch exhausted the 1008 KB inside the bar's getter). Every new deepest point of the run, 16 KB past the last, writes one
    /// line: the room used, the frames and how many stand in each counted image, and our own frames as offsets for atos -- the
    /// margin is read on every phone without waiting for a death.
    private static var deepestKB = 0
    static func noteDepth(_ place: String) {
        guard stackTop != 0, pthread_main_np() != 0 else { return }
        var here: UInt8 = 0
        let sp = withUnsafeMutablePointer(to: &here) { UInt(bitPattern: $0) }
        guard sp > stackBottom, sp < stackTop else { return }
        let usedKB = Int((stackTop &- sp) / 1024)
        guard usedKB >= deepestKB + 16 else { return }
        deepestKB = usedKB
        let cap = 8192
        let raw = UnsafeMutablePointer<UnsafeMutableRawPointer?>.allocate(capacity: cap)
        defer { raw.deallocate() }
        let n = Int(backtrace(raw, Int32(cap)))
        var counts = [Int](repeating: 0, count: gMontanaImageNames.count)
        var ours: [String] = []
        for i in 0..<n {
            let pc = UInt(bitPattern: raw[i]) & 0x0000_007F_FFFF_FFFF
            let j = montanaImageIndex(pc)
            counts[j] += 1
            if j == 0, ours.count < 40 { ours.append(String(pc &- gMontanaImageBase, radix: 16)) }
        }
        let images = gMontanaImageNames.indices.filter { counts[$0] > 0 }.map { "\(gMontanaImageNames[$0])=\(counts[$0])" }.joined(separator: ",")
        let line = "at=\(place) used_kb=\(usedKB) of_kb=\(Int((stackTop &- stackBottom) / 1024)) frames=\(n) images=\(images)"
        MontanaLog.event("MAIN STACK " + line + " ours=" + ours.joined(separator: ","))
        MontanaP2PTrace.mark("main_stack", line)
    }
    static func capture(limit: Int = 24) -> [String] {
        #if arch(arm64)
        var frames: [UInt] = []
        frames.reserveCapacity(limit + 2)
        guard port != 0, thread_suspend(port) == KERN_SUCCESS else { return [] }
        var state = arm_thread_state64_t()
        var count = mach_msg_type_number_t(MemoryLayout<arm_thread_state64_t>.size / MemoryLayout<UInt32>.size)
        let kr = withUnsafeMutablePointer(to: &state) {
            $0.withMemoryRebound(to: natural_t.self, capacity: Int(count)) { thread_get_state(port, ARM_THREAD_STATE64, $0, &count) }
        }
        if kr == KERN_SUCCESS {
            frames.append(UInt(state.__pc)); frames.append(UInt(state.__lr))
            var fp = UInt(state.__fp)
            while frames.count < limit, fp >= stackBottom, fp &+ 16 <= stackTop, fp % 8 == 0,
                  let f = UnsafePointer<UInt>(bitPattern: fp) {
                let next = f[0], lr = f[1]
                guard lr != 0 else { break }
                frames.append(lr)
                guard next > fp else { break }
                fp = next
            }
        }
        thread_resume(port)
        return frames.map(name)
        #else
        return []
        #endif
    }
    private static func name(_ raw: UInt) -> String {
        let a = raw & 0x0000_007F_FFFF_FFFF   // without the pointer-authentication bits
        var info = dl_info()
        guard dladdr(UnsafeRawPointer(bitPattern: a), &info) != 0, let base = info.dli_fbase else { return String(format: "0x%lx", a) }
        let image = info.dli_fname.map { String(cString: $0).split(separator: "/").last.map(String.init) ?? "?" } ?? "?"
        let off = a &- UInt(bitPattern: base)
        if let s = info.dli_sname, let sa = info.dli_saddr { return "\(image)+\(off) \(String(cString: s))+\(a &- UInt(bitPattern: sa))" }
        return "\(image)+\(off)"
    }
    /// The frames of the thread the system's report blames -- a hang's stalled thread or a crash's
    /// fallen one -- as binary+offset, the innermost first. THE ROOT OF THE REPORT'S TREE IS THE INNERMOST
    /// FRAME (measured 25.09, T1 16:04Z): the list was reversed on the belief that the root was the outermost,
    /// and every report read backwards -- the sampler's own stack put MTSearchField.updateUIView above UIKit's
    /// becomeFirstResponder, the report printed the two the other way round. Both stacks now read alike.
    /// How many threads the report's tree holds, which one it blames and how many frames each root carries.
    static func threadsLine(ofReport json: Data) -> String {
        guard let obj = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
              let stacks = obj["callStacks"] as? [[String: Any]] else { return "tree=unreadable bytes=\(json.count)" }
        let blamed = stacks.firstIndex { ($0["threadAttributed"] as? Bool) == true }.map(String.init) ?? "-"
        let roots = stacks.map { String(($0["callStackRootFrames"] as? [Any])?.count ?? -1) }.joined(separator: ",")
        return "threads=\(stacks.count) blamed=\(blamed) roots=\(roots) bytes=\(json.count)"
    }
    static func frames(ofReport json: Data, limit: Int = 24) -> String {
        guard let obj = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
              let stacks = obj["callStacks"] as? [[String: Any]] else { return "-" }
        let stack = stacks.first { ($0["threadAttributed"] as? Bool) == true } ?? stacks.first
        var frame = (stack?["callStackRootFrames"] as? [[String: Any]])?.first
        var out: [String] = []
        while let f = frame, out.count < limit {
            out.append("\(f["binaryName"] as? String ?? "?")+\(f["offsetIntoBinaryTextSegment"] as? Int ?? 0)")
            frame = (f["subFrames"] as? [[String: Any]])?.first
        }
        return out.joined(separator: " < ")   // the root first: the root is the innermost frame
    }
}


/// ONE OWNER OF EVERY PICTURE CACHE (the critic 25.09, the fleet's diaries: three phones stood in the background with
/// 140–420 MB — the wall's pictures alone were let 160 MB — and were ended at the door within seconds, the person opening the
/// app again cold; four «terminated … unexplained» in one morning). A cache is born through this door and named; leaving the
/// screen, and at the system's warning, every cache is emptied here, once, and the footprint is measured before and after —
/// the number the memory killer reads. An NSCache purges itself only on a warning a background run never gets.
/// EMPTIED ONLY BY THE PERSON'S CLEAR (the author 03.10): let go at the door, a photo came back black on return —
/// Data and Storage holds the one call.
enum MontanaCaches {
    private static let lock = NSLock()
    private static var drops: [(name: String, drop: () -> Void)] = []
    static func kept<K: AnyObject, V: AnyObject>(_ name: String, cost: Int = 0, count: Int = 0) -> NSCache<K, V> {
        let c = NSCache<K, V>()
        if 0 < cost { c.totalCostLimit = cost }
        if 0 < count { c.countLimit = count }
        register(name) { c.removeAllObjects() }
        return c
    }
    static func register(_ name: String, _ drop: @escaping () -> Void) {
        lock.lock(); drops.append((name, drop)); lock.unlock()
    }
    /// Every cache emptied; the number of them, for the diary.
    @discardableResult
    static func dropAll(why: String) -> Int {
        lock.lock(); let all = drops; lock.unlock()
        for d in all { d.drop() }
        return all.count
    }
}
final class MontanaTelemetry {
    static let shared = MontanaTelemetry()
    private let ioq = DispatchQueue(label: "montana.telemetry.io")
    private var lastHeartbeat: TimeInterval = Date().timeIntervalSince1970
    /// Seconds since the main loop last beat — the length of the sleep the process just left.
    var sleptFor: TimeInterval { Date().timeIntervalSince1970 - lastHeartbeat }

    static var logURL: URL { MontanaLog.url(.telemetry) }

    /// An event into the journal. One record, one call: the tree has one journal, and telemetry writes by it.
    func event(_ text: String) { MontanaLog.event(text) }

    private static var crashMarkURL: URL { MontanaLog.url(.telemetry).deletingLastPathComponent().appendingPathComponent("run.crashed") }

    func install() {
        gMontanaCrashFD = open(Self.logURL.path, O_WRONLY | O_CREAT | O_APPEND, 0o644)
        // The run before left its word here if it fell; read it, then open the file anew for this run.
        let lastCrash = (try? String(contentsOf: Self.crashMarkURL, encoding: .utf8)) ?? ""
        gMontanaCrashMarkFD = open(Self.crashMarkURL.path, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
        gMontanaCrashText = .allocate(capacity: 96)
        gMontanaCrashFrames = .allocate(capacity: 64)
        MontanaLog.onTelemetryRotate = {
            if gMontanaCrashFD >= 0 { close(gMontanaCrashFD) }
            gMontanaCrashFD = open(MontanaLog.url(.telemetry).path, O_WRONLY | O_CREAT | O_APPEND, 0o644)
        }
        montanaInstallSignalHandlers()   // on a stack of its own: an exhausted stack is witnessed too (03.10)
        NSSetUncaughtExceptionHandler { ex in
            let st = ex.callStackSymbols.prefix(24).joined(separator: " <- ")
            // Written through the crash descriptor, synchronously: the journal queue is
            // asynchronous and the process aborts right after this handler returns. The record wears
            // the journal's own time (23.09), so a filter by the hour finds it.
            let line = "\n" + MontanaLog.stamp() + " === CRASH EXCEPTION t=\(Int(Date().timeIntervalSince1970)) \(ex.name.rawValue): \(ex.reason ?? "") | \(st) ===\n"
            if gMontanaCrashFD >= 0 { _ = line.withCString { write(gMontanaCrashFD, $0, strlen($0)) }; fsync(gMontanaCrashFD) }
            if gMontanaCrashMarkFD >= 0 {
                gMontanaCrashMarked = true
                _ = ("exception-" + ex.name.rawValue).withCString { write(gMontanaCrashMarkFD, $0, strlen($0)) }
                fsync(gMontanaCrashMarkFD)
            }
        }
        // NO EXIT GOES UNWITNESSED (05.09). Signals and exceptions are one witness; a kill by the
        // watchdog, by memory, by a hand on the switcher or before our first line leaves them
        // nothing to write. The run keeps a sentinel: its state and its last breath. The next
        // launch judges the previous run BEFORE its own launch line: died on screen — a finding;
        // reclaimed in background — the system's norm; died before the screen — a system start.
        judgePreviousRun(crash: lastCrash)
        aliveState = "launch"; writeAlive(force: true)
        // The screen moments come from the system's notifications: under the scene lifecycle
        // UIKit never calls applicationDidBecomeActive / applicationWillResignActive.
        NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in self?.markActive(true) }
        NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in self?.markActive(false) }
        NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { _ in
            // THE FOOTPRINT AT THE DOOR (23.09, the critic): the system kills a run that leaves the screen too heavy,
            // and the diary knew the memory only in the next run's line of death — what grew could not be shown.
            // The pictures stay at the door (the author 03.10): emptied here, a photo came back black — only the
            // person's Clear lets them go (MontanaCaches).
            let mem = MontanaTelemetry.footprintMB()
            MontanaLog.event("SCENE background mem_mb=\(mem)"); MontanaP2PTrace.mark("scene", "background mem_mb=\(mem)")
        }
        NotificationCenter.default.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { _ in
            MontanaLog.event("SCENE foreground"); MontanaP2PTrace.mark("scene", "foreground"); AppDelegate.sceneSeen = true
        }
        NotificationCenter.default.addObserver(forName: UIApplication.willTerminateNotification, object: nil, queue: nil) { [weak self] _ in
            // The sentinel is not erased but STAMPED (17.09, the critic): a run that ended by the system's
            // willTerminate — a swipe in the switcher, or the system — left no line at the next launch,
            // and a death a second after every background could not be told from a hand.
            self?.aliveState = "terminated"; self?.writeAlive(force: true, sync: true)
            MontanaLog.event("=== TERMINATE clean ==="); MontanaP2PTrace.mark("scene", "terminate")
        }
        // THE CAUSE OF A DEATH IS NAMED, NOT GUESSED (the author's word 12.09: «the diary must name
        // the cause of a death»). The sentinel carries the facts a kill leaves behind — the resident
        // footprint, a memory warning, a stalled main thread — and the judge adds what the next launch
        // can see for itself: a reinstall and a reboot.
        NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.memWarned = true
            let mem = Self.footprintMB()
            MontanaLog.event("MEMORY warning mem_mb=\(mem)")
            MontanaP2PTrace.mark("memory_warning", "mem_mb=\(mem)")
            self.writeAlive(force: true)   // the picture caches are NSCaches and give way here by their own policy (03.10)
        }
        // The battery answers -1 until monitoring is on; on from the first line, so the first call
        // of a run reads a level and not a placeholder.
        UIDevice.current.isBatteryMonitoringEnabled = true
        MXMetricManager.shared.add(MontanaMetricSink.shared)
        startHeartbeat(); startWatchdog()
        // The build number on the launch line: without it the journal cannot say which process
        // wrote an event, and a diagnosis once stalled on exactly that question.
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        MontanaLog.event("=== launch v\(build) \(UIDevice.current.systemName) \(UIDevice.current.systemVersion) \(UIDevice.current.model) ===")
        MontanaLog.event(montanaImageLine())   // the base the crash line's raw frames are read against (03.10)
        // The notification extension writes into the app group, which a device cannot read
        // directly — carry it into the common journal so diagnostics stay reachable.
        Self.carryExtensionLines()
        // The hand-run stage tests lean on three facts about the whole run: whether an identity is
        // held, whether the frozen vectors of the Canon reproduce on THIS device, and what the
        // network path was at every moment. Flags, counts and durations only — the journal proves
        // the run, it must not become a record of the person.
        MontanaP2PTrace.mark("audit_launch",
            "identity=\(MontanaSeed.hasSeed ? 1 : 0) bundle=\(Bundle.main.bundleIdentifier ?? "?")")
        DispatchQueue.global(qos: .utility).async {
            MontanaP2PTrace.mark("audit_canon",
                "pipe=\(MTPipe.agreesWithCanon() ? 1 : 0) knock=\(MontanaFirstContact.agreesWithCanon() ? 1 : 0)")
        }
        MontanaNetWitness.start()
    }

    /// Lines the extensions wrote while the app slept: carried into the common journal so the
    /// next shipment takes them along. Called at launch, on every silent wake and on foreground —
    /// the same breaths that ship the journal itself.
    static func carryExtensionLines() {
        guard let d = MontanaKeychain.get("nseLog"), let txt = String(data: d, encoding: .utf8),
              !txt.isEmpty else { return }
        MontanaKeychain.set("nseLog", Data())
        for line in txt.split(separator: "\n") { MontanaLog.event("EXT \(line)") }
    }

    // The facility keeps the crash descriptor, the heartbeat and the watchdog. Writing is neither its
    // job nor its code: every line in the app and in both extensions goes through MontanaLog.event.


    /// Zero means "not active"; otherwise it is the instant from which the app has been active without a break.
    private(set) var activeSince: TimeInterval = 0
    /// How many times the screen was left. A reading that must lie wholly inside one active
    /// stretch (the main-thread probe) compares this before and after.
    private(set) var resigns = 0
    private var aliveHang = 0.0      // the main thread's current stall, seconds; 0 when it beats
    private var memWarned = false    // the system warned about memory during this run

    /// The app entered the active state or left it. The watchdog counts as stuck only the thread that
    /// was supposed to beat -- in sleep there is legitimately no beat.
    func markActive(_ on: Bool) {
        if on { lastHeartbeat = Date().timeIntervalSince1970; activeSince = lastHeartbeat }
        else { activeSince = 0; resigns += 1 }
        aliveState = on ? "active" : "background"; if !on { bgAt = Date().timeIntervalSince1970 }; writeAlive(force: true)
        MontanaLog.event(on ? "SCENE active" : "SCENE resign")
        MontanaP2PTrace.mark("scene", on ? "active" : "resign")
    }

    // ── the sentinel of the run (05.09) ──
    private static var aliveURL: URL { MontanaLog.url(.telemetry).deletingLastPathComponent().appendingPathComponent("run.alive") }
    private var aliveState = "launch"
    private var bgAt: TimeInterval = 0        // when the screen was last left (the judge reads how long a run stood at the door)
    private let runStarted = Date().timeIntervalSince1970
    private var aliveLastWrite: TimeInterval = 0
    private func writeAlive(force: Bool = false, sync: Bool = false) {
        let now = Date().timeIntervalSince1970
        guard force || now - aliveLastWrite >= 5 else { return }
        aliveLastWrite = now
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        let mem = Self.footprintMB(), warn = memWarned ? 1 : 0, hang = Int(aliveHang)
        let line = "\(build) \(self.aliveState) \(Int(now)) mem=\(mem) warn=\(warn) hang=\(hang) tcc=\(MTSystemAccess.stamp()) up=\(Int(now - runStarted)) bg=\(bgAt == 0 ? -1 : Int(now - bgAt))"
        // A termination writes on the calling thread: the process is gone before a queue would run.
        if sync { try? line.data(using: .utf8)?.write(to: Self.aliveURL, options: .atomic) }
        else { ioq.async { try? line.data(using: .utf8)?.write(to: Self.aliveURL, options: .atomic) } }
    }
    private func retireSentinel() { try? FileManager.default.removeItem(at: Self.aliveURL) }
    private func judgePreviousRun(crash: String) {
        guard let d = try? Data(contentsOf: Self.aliveURL), let s = String(data: d, encoding: .utf8) else { return }
        let parts = s.split(separator: " ").map(String.init)
        let build = parts.count > 0 ? parts[0] : "?"
        let state = parts.count > 1 ? parts[1] : "?"
        let at = parts.count > 2 ? (Double(parts[2]) ?? 0) : 0
        let age = Int(Date().timeIntervalSince1970 - at)
        // The facts of the last breath, then the verdict. The first fact is the dying run's own word
        // (run.crashed: the signal or the exception that felled it); two causes are facts of this launch
        // (another build stands here; the kernel booted after the last breath); two are suspicions
        // named as such (the main thread stood; memory was short); the rest stays honestly unexplained.
        var facts: [String: String] = [:]
        for kv in parts.dropFirst(3) {
            let p = kv.split(separator: "=", maxSplits: 1)
            if p.count == 2 { facts[String(p[0])] = String(p[1]) }
        }
        let nowBuild = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        let mem = facts["mem"] ?? "-", warn = facts["warn"] ?? "-", hang = facts["hang"] ?? "-"
        let up = Int(facts["up"] ?? "") ?? -1, bg = Int(facts["bg"] ?? "") ?? -1   // how long the run lived, how long it stood at the door
        let ramMB = Int(ProcessInfo.processInfo.physicalMemory / 1_048_576)
        let fell = crash.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: " ", with: "_")
        let cause: String
        if !fell.isEmpty { cause = "crash-" + fell }
        else if build != nowBuild { cause = "reinstalled" }
        else if Self.bootTime() > at { cause = "rebooted" }
        // A privacy switch moved while the run was away: iOS ends the app for it, by its own rule — a fact, not a suspicion.
        else if let then = facts["tcc"], !MTSystemAccess.moved(from: then, to: MTSystemAccess.stamp()).isEmpty {
            cause = "access-changed-" + MTSystemAccess.moved(from: then, to: MTSystemAccess.stamp()).joined(separator: "+")
        }
        else if (Int(hang) ?? 0) > 0 { cause = "watchdog-suspect" }
        else if warn == "1" || (Int(mem) ?? 0) * 2 >= ramMB { cause = "memory-suspect" }
        else { cause = "unexplained" }
        let tail = " cause=\(cause) mem_mb=\(mem) warn=\(warn) hang_s=\(hang)" + (bg < 0 ? "" : " bg_s=\(bg)")
        if state == "active" {
            MontanaLog.event("=== PREVIOUS RUN DIED ON SCREEN build=\(build) last_beat_age=\(age)s\(tail) ===")
            MontanaP2PTrace.mark("prev_exit", "died-on-screen build=\(build) age=\(age)s" + tail)
        } else if state == "terminated" {
            // A RUN ENDED AT THE DOOR IS NAMED FOR WHAT IT IS (the critic 25.09, four «unexplained» in a morning): willTerminate
            // reaches only a run still working in the background — a swipe in the switcher, or the killer's pick of a heavy
            // run; nothing else ends a run this way. «unexplained» here read as a crash; it is a hand or the system.
            let named = cause == "unexplained" ? tail.replacingOccurrences(of: "cause=unexplained", with: "cause=swipe-or-system") : tail
            MontanaLog.event("=== PREVIOUS RUN TERMINATED BY THE SYSTEM build=\(build) last_beat_age=\(age)s (a swipe in the switcher, or the system)\(named) ===")
            MontanaP2PTrace.mark("prev_exit", "terminated build=\(build) age=\(age)s" + named)
        } else if state == "launch", 30 <= up {
            // A RUN THAT NEVER SHOWED A SCREEN AND LIVED (a wake's run: the letter, the ring, the refresh) ended as the system
            // ends every background run — its norm, not a death before the screen (the Mac's three «died-before-screen»
            // of 25.09 had lived 7–30 minutes).
            MontanaLog.event("=== PREVIOUS BACKGROUND RUN ENDED build=\(build) lived=\(up)s last_beat_age=\(age)s (the system's norm)\(tail) ===")
            MontanaP2PTrace.mark("prev_exit", "background-run-ended build=\(build) lived=\(up)s age=\(age)s" + tail)
        } else if state == "launch" {
            MontanaLog.event("=== PREVIOUS RUN DIED BEFORE REACHING THE SCREEN build=\(build) last_beat_age=\(age)s\(tail) ===")
            MontanaP2PTrace.mark("prev_exit", "died-before-screen build=\(build) age=\(age)s" + tail)
        } else if !fell.isEmpty {
            // A run that fell in the background is not the system's norm: it wrote its own word as it fell.
            MontanaLog.event("=== PREVIOUS RUN CRASHED IN BACKGROUND build=\(build) last_beat_age=\(age)s\(tail) ===")
            MontanaP2PTrace.mark("prev_exit", "crashed-in-background build=\(build) age=\(age)s" + tail)
        } else {
            MontanaLog.event("=== PREVIOUS RUN RECLAIMED IN BACKGROUND build=\(build) last_beat_age=\(age)s (the system's norm)\(tail) ===")
            MontanaP2PTrace.mark("prev_exit", "reclaimed-in-background build=\(build) age=\(age)s" + tail)
        }
    }

    private func startHeartbeat() {
        MTMainStack.remember()   // the thread that beats is the thread the watchdog will read
        let t = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.lastHeartbeat = Date().timeIntervalSince1970
        }
        RunLoop.main.add(t, forMode: .common)
    }
    /// The watchdog counts as stuck only the thread that WAS SUPPOSED to beat.
    ///
    /// The beat hangs on the main loop, and in app sleep that loop legitimately does not turn -- and
    /// the former watchdog called sleep a hang: the journal held "stuck for 162 seconds" where the
    /// phone simply kept the app asleep. A reading that does not measure the value it names is worse
    /// than no reading: it leads the search for a cause astray. So the watchdog looks only at
    /// intervals spent wholly in the active state.
    private func startWatchdog() {
        let w = Thread { [weak self] in
            while true {
                Thread.sleep(forTimeInterval: 1.0)
                guard let self else { return }
                self.writeAlive()   // the run breathes into its sentinel every five seconds
                guard self.activeSince > 0 else { continue }   // asleep -- nothing to count
                let now = Date().timeIntervalSince1970
                let stall = now - self.lastHeartbeat
                // The interval must lie wholly inside the active state, or sleep gets into it and the
                // measure lies again. WHOLLY INCLUDES ITS FIRST SECOND (25.09, the tablet): a thread that never beat
                // after the activation has lastHeartbeat equal to activeSince, and «greater than» read that as «not
                // inside» — two hangs of the whole activation stood with hang=0, judged «unexplained», until the
                // system's own report named them (0x8BADF00D).
                guard stall > 4.0, now - self.activeSince >= stall else { continue }
                MontanaLog.event("HANG main-thread stalled \(String(format: "%.1f", stall))s")
                self.aliveHang = stall; self.writeAlive(force: true)   // the sentinel knows the thread stood — a kill now has a named suspect
                var shots = 0
                while self.activeSince > 0, Date().timeIntervalSince1970 - self.lastHeartbeat > 4.0 {
                    if shots < 3 {   // the stack of the stuck thread, three times over six seconds
                        shots += 1
                        MontanaLog.event("HANG stack \(shots): " + MTMainStack.capture().joined(separator: " < "))
                    }
                    Thread.sleep(forTimeInterval: 2.0)
                    self.aliveHang = Date().timeIntervalSince1970 - self.lastHeartbeat; self.writeAlive(force: true)
                }
                self.aliveHang = 0
                MontanaLog.event("HANG recovered")
            }
        }
        w.name = "montana.watchdog"; w.stackSize = 256 * 1024; w.start()
    }

    /// The resident footprint of this process, in megabytes — the number the memory killer reads.
    static func footprintMB() -> Int {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
        }
        return kr == KERN_SUCCESS ? Int(info.phys_footprint / 1_048_576) : -1
    }
    /// When this device last booted, by the kernel's own clock; 0 when it will not say.
    static func bootTime() -> TimeInterval {
        var tv = timeval(); var size = MemoryLayout<timeval>.size
        var mib: [Int32] = [CTL_KERN, KERN_BOOTTIME]
        guard sysctl(&mib, 2, &tv, &size, nil, 0) == 0 else { return 0 }
        return TimeInterval(tv.tv_sec)
    }
}

/// THE SYSTEM'S OWN WINDOW (18.09, the author's word: «closes the case of no network and nobody
/// writing»). A wake needs somebody on the other end to write; the system grants a window of its
/// own every few hours to an app that asks — no push, no correspondent. In it the queue rides and
/// the box is read, exactly as on a wake: one road for every background breath. The next window is
/// asked for FIRST — a handler killed at its deadline must not lose the rhythm. The identifier is
/// the contour's own (MontanaContour.wakeTask) and stands in the plist under the same name.
enum MontanaBackgroundRefresh {
    static let id = MontanaContour.wakeTask
    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: id, using: .main) { task in
            guard let t = task as? BGAppRefreshTask else { task.setTaskCompleted(success: false); return }
            handle(t)
        }
    }
    static func schedule() {
        let req = BGAppRefreshTaskRequest(identifier: id)
        req.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        do {
            try BGTaskScheduler.shared.submit(req)
            MontanaP2PTrace.markFolded("bg_refresh", "asked for the next window", window: 600)
        } catch {
            MontanaP2PTrace.markFolded("bg_refresh", "the request was refused: \(error.localizedDescription)", window: 600)
        }
    }
    private static func handle(_ task: BGAppRefreshTask) {
        schedule()
        MontanaP2PTrace.mark("bg_refresh", "the system's window — the queue rides, the box is read")
        let finish = DispatchWorkItem {
            MontanaP2PTrace.mark("bg_refresh", "done")
            task.setTaskCompleted(success: true)
        }
        task.expirationHandler = {
            finish.cancel()
            MontanaP2PTrace.mark("bg_refresh", "expired by the system")
            task.setTaskCompleted(success: false)
        }
        MontanaWakeDoor.arrived("refresh")
        MontanaWakePush.fetchBoxKick()
        MontanaWakePush.drainInbox()
        // THE NAME IS RENEWED IN THE SYSTEM'S WINDOW TOO (24.09, the critic's P6): a renewal that waited for the
        // person's return let a name lapse between two openings; the question «is it due» is the same one.
        if let mn = MontanaSeed.mnemonic, let master = MontanaQueueKeys.masterSeed(mn) {
            MontanaNames.keepInStep(masterSeed: master)
        }
        // The diary is not shipped here: the phone speaks at its three moments (P-60), and the
        // marks of this window ride with the next of them.
        DispatchQueue.main.asyncAfter(deadline: .now() + 20, execute: finish)
    }
}


/// THE ONE DOOR EVERY BACKGROUND WAKE PASSES (the author's word 20.09). Four roads woke this app in
/// the background — the voip push, the letter push, the bare ring, the system's refresh window — and
/// each decided for itself whether the node channels are to be reopened. Two remembered, two did
/// not: a socket that lived across sleep counts as alive, the first letter after a wake went into it
/// and waited for the timeout — 5.09 s, and once 29.8 s until the next wake (an iPhone 17, 19.09
/// 15:19 and 15:12); the one instant wake of that hour was the idle rule retiring the channels by
/// luck. The fact of sleep is the app's own: the main-loop heartbeat stops while the process is
/// frozen, and the gap between beats is the length of the sleep. A gap says «the channels are
/// corpses» — they are dropped and the nodes dialed this instant (reprobeNode); no gap says «the
/// channels are live» — nothing is torn down on a letter into a running app (the 24.08 storm: 782
/// knocks from doors killing each other's handshakes). The guard (mt-layout-check 10) refuses a
/// build where a wake road stands outside this door.
enum MontanaWakeDoor {
    /// Longer than this without a heartbeat = the process was frozen; the beat itself is 0.5 s.
    static let sleepGapS: TimeInterval = 3
    /// THE WAKE'S AGE AND THE WAKE'S VERDICT (the author's word 20.09: «I want to see the push land on
    /// the phone, and whether the ring died for want of a node or for something else»). The node stamps
    /// every push with the moment it sent it (`at`); the phone reads it at the door — the age is the
    /// time the push spent between Apple and this phone, the one stretch no line of ours runs on.
    /// Twelve seconds later one line judges the wake: did a node come up, did the ring post, did the
    /// offer arrive, did ICE start — and names the first link that did not. A verdict other than ok
    /// ships the diary at once (isFailure). A burst of wakes is one wake for the verdict.
    static let verdictAfterS: TimeInterval = 12
    /// A wake that travelled longer than this is stale: the longest a wake's word lives at the node.
    static let staleAfter: TimeInterval = 90
    private struct Pending { let why: String; let t0: Date; let age: Int?; var expectsCall = false
                             var node: Int?; var ring: Int?; var offer: Int?; var ice: Int? }
    private static var pending: Pending?
    private static let lock = NSLock()

    static func arrived(_ why: String, at: Int? = nil) {
        let now = Date()
        let gap = MontanaTelemetry.shared.sleptFor
        let slept = sleepGapS < gap
        let age = at.map { max(0, Int(now.timeIntervalSince1970) - $0) }
        MontanaP2PTrace.mark("wake", "why=\(why) gap_s=\(Int(gap)) reprobe=\(slept ? 1 : 0) age_s=\(age.map(String.init) ?? "-")")
        lock.lock()
        if pending == nil {
            let held = !MontanaP2PDirect.shared.livePathKeys().isEmpty
            pending = Pending(why: why, t0: now, age: age, node: held ? 0 : nil)
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + verdictAfterS) { judge() }
        }
        lock.unlock()
        MontanaP2PNode.shared.autoStart()
        if slept { MontanaP2PNode.shared.reconnectNow() }
        AppDelegate.drainOutgoingOnWake(why)
    }

    /// A link of the wake reported by the place where it happens: node (the first door answered),
    /// ring (the call posted to the system), offer (the caller's offer in hand), ice (checks began),
    /// expect-call (this wake carries a call — the verdict demands ring, offer and ice).
    static func note(_ what: String) {
        lock.lock(); defer { lock.unlock() }
        guard var p = pending else { return }
        let ms = Int(Date().timeIntervalSince(p.t0) * 1000)
        switch what {
        case "node":  if p.node == nil { p.node = ms }
        case "ring":  if p.ring == nil { p.ring = ms }
        case "offer": if p.offer == nil { p.offer = ms }
        case "ice":   if p.ice == nil { p.ice = ms }
        case "expect-call": p.expectsCall = true
        default: break
        }
        pending = p
    }

    private static func judge() {
        lock.lock(); let p = pending; pending = nil; lock.unlock()
        guard let p else { return }
        let verdict: String
        if let a = p.age, Self.staleAfter < Double(a) { verdict = "stale" }
        else if p.node == nil { verdict = "no-node" }
        else if p.expectsCall, p.ring == nil { verdict = "no-ring" }
        else if p.expectsCall, p.offer == nil { verdict = "no-offer" }
        else if p.expectsCall, p.ice == nil { verdict = "no-ice" }
        else { verdict = "ok" }
        func f(_ v: Int?) -> String { v.map(String.init) ?? "-" }
        MontanaP2PTrace.mark("wake_verdict", "why=\(p.why) age_s=\(f(p.age)) node_ms=\(f(p.node)) call=\(p.expectsCall ? 1 : 0) ring_ms=\(f(p.ring)) offer_ms=\(f(p.offer)) ice_ms=\(f(p.ice)) verdict=\(verdict)")
    }
}

#if targetEnvironment(macCatalyst)
enum MTRetiredSupervisor {
    static func leave() -> Never {
        if let id = Bundle.main.bundleIdentifier {
            let agent = SMAppService.agent(plistName: id + ".VPNRecovery.plist")   // RETIRED-VPN-KEY: the old agent's own file name
            let done = DispatchSemaphore(value: 0)
            agent.unregister { _ in done.signal() }
            _ = done.wait(timeout: .now() + 5)
        }
        exit(EXIT_SUCCESS)
    }
}
#endif
