// MTYouTube.swift -- YouTube inside Montana. The author's words 17.10.2026 UTC: 13:3x-13:4x, a social network that plays the music
// of a YouTube link inside itself «breaks nothing -- do it so here», «search YouTube's music at once, and a link plays inside our
// app»; 15:0x, integrate it natively -- the mini player works, no extra windows in the chat, everything plays at once, nothing takes
// the sound before the person's own tap and nothing cuts another app's music; 15:1x, «YouTube in our app like picture in picture»,
// «the native picture in picture, the system's, when YouTube is turned on»; 18.10.2026 08:1x, «the picture in picture is not alive
// either and nothing takes a tap -- the behaviour as in the chat everywhere, loading natively into our mini player».
// A YouTube link in a letter, in a card or on a wall, and a row the music page's search found, play in YouTube's own player inside
// our mini player (MTYouTubeStage): the person stays on the screen they were on, the window stands over it and moves under the
// finger, and the system's full-screen player is one mark away.
//
// THE PLAYER IS YOUTUBE'S OWN AND IT IS SEEN (YouTube API Services: Developer Policies and Required Minimum Functionality, read
// 17.10.2026). The embedded player loads in the platform's web view («WKWebView or SFSafariViewController») and names this app by
// the Referer -- «the domain name must be your application identifier». On the card it is at least 200 by 200 points («a viewport
// that is at least 200px by 200px») and nothing lies over it or clips it («You must not display overlays, frames, or other visual
// elements in front of any part of a YouTube embedded player»). It plays only once it is seen («must not initiate an automatic
// playback until the player is visible»): the card stands on the screen before the player loads. It is never a background player
// («a player that is not displayed in the page, tab, or screen that the user is viewing»): the system's picture in picture is a
// window on the very screen the person looks at, and a card nobody sees rests -- the app leaving the screen rests a video on the
// card. No byte of a video is kept («must not ... download ... cache, or store copies of YouTube audiovisual content») and its
// sound is never taken apart from its picture. The web view's store is the ephemeral one: no cookie outlives the player.
//
// THE FULL SCREEN IS WEBKIT'S OWN (read 17.10.2026 in WebKit's source): the page's video enters it by its presentation mode, which
// HTMLVideoElement::setPresentationMode grants on a person's gesture (MediaElementSession::fullscreenPermitted); WKWebView's
// evaluateJavaScript runs «forceUserGesture:YES» -- the tap on the mark is the gesture. The configuration allows no picture in
// picture (allowsPictureInPictureMediaPlayback), so the system's window is never born from our player.
//
// THE SOUND IS TAKEN BY THE TAP AND GIVEN BACK BY THE PAUSE: no web view exists before the tap; the player holds the sound by the
// name «youtube» while it plays (MontanaAudioSession), lets it go at its pause and its end, and the last of ours to let go lowers
// the session with the word that lets another app's music go on. A sound of ours that starts rests YouTube where it stands: one
// sound at a time.
//
// THE SEARCH GOES BY OUR OWN SERVICE (Info.plist MontanaService): YouTube's key lives there, never in this open code, where anyone could
// spend its daily count; YouTube sees the service ask, never the person's address. The words are asked once they settle -- the
// count is a hundred searches a day for the whole app -- and a service that does not answer shows no YouTube row at all.

import SwiftUI
import UIKit
import WebKit

enum MTYouTube {
    /// One video YouTube's search found: its id, its title and its channel as YouTube gives them, its length in seconds.
    struct Found: Decodable, Equatable {
        let id: String
        let t: String
        let c: String
        let s: Int
    }
    private struct Answer: Decodable { let items: [Found] }

    /// The music page's rows of YouTube: the head that names the source, then a row for each video.
    static let headRow = "youtube:"
    static let rowPrefix = "youtube:v:"
    static func rows(_ list: [Found]) -> [Chat] {
        guard !list.isEmpty else { return [] }
        let head = Chat(name: headRow, lastMessage: "", time: "", unread: 0, status: "", convId: headRow)
        return [head] + list.map { f in Chat(name: rowPrefix + f.id, lastMessage: "", time: "", unread: 0, status: "", convId: rowPrefix + f.id) }
    }
    static func found(_ c: Chat, in list: [Found]) -> Found? {
        guard c.name.hasPrefix(rowPrefix) else { return nil }
        let id = String(c.name.dropFirst(rowPrefix.count))
        return list.first { f in f.id == id }
    }

    /// A tap on a link: a YouTube video plays here; any other link is not this player's (false).
    static func play(_ url: URL, title: String? = nil) -> Bool {
        guard let tube = MTLinkPreviewBuilder.youtube(url) else { return false }
        play(tube.id, title: title)
        return true
    }
    /// A tap on a video: YouTube's own player over the screen the person is on, then the system's picture in picture.
    static func play(_ id: String, title: String? = nil, channel: String? = nil) {
        onMain { MTYouTubeStage.shared.play(id, title: title, channel: channel) }
    }
    /// YouTube sounds now: the sound's ledger asks the player itself (MontanaAudioSession).
    static var sounds = false
    /// A sound of ours starts: YouTube rests where it stands, its window stays -- one sound at a time.
    static func rest() {
        guard sounds else { return }
        onMain { MTYouTubeStage.shared.rest() }
    }
    /// The stage is the screen's and lives on the main thread; every caller is a tap or a player's start.
    private static func onMain(_ work: @escaping @MainActor () -> Void) {
        if Thread.isMainThread { MainActor.assumeIsolated { work() } }
        else { DispatchQueue.main.async { MainActor.assumeIsolated { work() } } }
    }

    /// Our own service on Montana's site, where YouTube's key lives.
    private static var service: String {
        "https://" + (Bundle.main.object(forInfoDictionaryKey: "MontanaService") as? String ?? "").lowercased() + "/b/v1"
    }

    /// YouTube's music for the words, found by our service; nil when the service does not answer.
    static func search(_ words: String) async -> [Found]? {
        var c = URLComponents(string: service + "/tube/search")
        c?.queryItems = [URLQueryItem(name: "q", value: words)]
        guard let u = c?.url else { return nil }
        var q = URLRequest(url: u, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        q.httpMethod = "GET"
        guard let got = try? await URLSession.shared.data(for: q), (got.1 as? HTTPURLResponse)?.statusCode == 200,
              let answer = try? JSONDecoder().decode(Answer.self, from: got.0) else { return nil }
        return answer.items.filter { f in f.id.count == 11 }
    }

    /// The Referer the player is named by: this app's own identifier as a web address (Required Minimum Functionality).
    static var referer: String { "https://" + (Bundle.main.bundleIdentifier ?? "montana").lowercased() }
    /// The embedded player's own page on the privacy-enhanced host: inline, and starting at once -- the person's tap asked for it.
    static func embed(_ id: String) -> URL? {
        var c = URLComponents(string: "https://www.youtube-nocookie.com/embed/" + id)
        c?.queryItems = [URLQueryItem(name: "playsinline", value: "1"), URLQueryItem(name: "autoplay", value: "1"),
                         URLQueryItem(name: "rel", value: "0")]
        return c?.url
    }
    /// The video on YouTube itself, for the mark that leaves for it.
    static func watch(_ id: String) -> URL? { URL(string: "https://www.youtube.com/watch?v=" + id) }

    /// The source named over its rows (Developer Policies: «make clear to the viewer that YouTube is the source»).
    static var head: some View {
        Label { Text("YouTube") } icon: { Image(systemName: "play.rectangle.fill") }
            .font(.footnote.weight(.semibold))
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 4)
    }
}

/// THE ONE PLAYER, OUR MINI PLAYER (the author's words 18.10.2026 08:1x UTC: «the picture in picture is not alive either and nothing
/// takes a tap; the behaviour must be as in the chat everywhere, and it must load natively into our mini player»; «this must be one
/// function, behaving always the same by the constitution»). T1 08:05:45Z: the video went into the system's picture in picture
/// from a stage standing on the window outside every controller, and from that moment not one touch reached the app -- the main
/// thread free, no word of the player after. The system's window is not asked for: the web view allows no picture in picture, so
/// its machinery is never born, and YouTube's own player plays inline in our mini player -- a rounded window over the screen the
/// person is on, standing in the root controller's view, YouTube's player in it at the least size YouTube's policies allow and
/// nothing of ours over it, our bar under it: the full-screen mark (the system's own full-screen player, whose Done brings the mini
/// player back) and the close mark. The bar carries the window: a drag moves it, the release sets it into the nearest corner.
/// Every road that plays a video -- a letter, a card, a wall, a peer's page, the music page's search -- comes here (MTYouTube.play),
/// so it behaves one way everywhere. The app leaving the screen rests the video: never a background player.
@MainActor final class MTYouTubeStage: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    static let shared = MTYouTubeStage()
    private static let hold = "youtube"   // the player's name in the sound's ledger (MontanaAudioSession)
    private static let channel = "tube"
    /// The player's own events, told to the diary by their names alone -- no video is ever named there -- and the page's
    /// presentation mode with whether the video plays at that moment.
    private static let listen = "['playing','pause','ended','error'].forEach(function(e){document.addEventListener(e,function(){try{window.webkit.messageHandlers.tube.postMessage(e)}catch(x){}},true)});document.addEventListener('webkitpresentationmodechanged',function(ev){try{var v=ev.target;window.webkit.messageHandlers.tube.postMessage('mode '+v.webkitPresentationMode+(v.paused?' paused':' playing'))}catch(x){}},true)"
    private static let wholeScript = "(function(){var v=document.querySelector('video');if(!v){return 'no video'}if(v.webkitSupportsPresentationMode&&v.webkitSupportsPresentationMode('fullscreen')){v.webkitSetPresentationMode('fullscreen');return 'asked'}if(v.webkitEnterFullscreen){v.webkitEnterFullscreen();return 'entered'}return 'not supported'})()"
    private static let pauseScript = "document.querySelectorAll('video').forEach(function(v){v.pause()})"
    private static let resumeScript = "document.querySelectorAll('video').forEach(function(v){v.play()})"
    private static let tall: CGFloat = 200   // YouTube's least viewport: «at least 200px by 200px»
    private static let bar: CGFloat = 44     // a target the finger takes at once

    private(set) var id: String?
    private var web: WKWebView?
    private var stage: UIView?
    private var whole = false      // the video stands in the system's full-screen player
    private var leaving: NSObjectProtocol?

    override init() {
        super.init()
        // NEVER A BACKGROUND PLAYER: the app leaving the screen rests the video where it stands.
        leaving = NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification, object: nil,
                                                         queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.rest() }
        }
    }

    func play(_ id: String, title: String?, channel: String?) {
        guard !MontanaAudioSession.refusedUnderCall("YouTube") else { return }
        if self.id == id, let w = web {
            // The same video asked again plays on where it stands -- in our mini player or the system's full-screen player.
            MontanaTrace.mark("youtube", "again whole=\(whole ? 1 : 0)")
            if !whole { show() }
            w.evaluateJavaScript(Self.resumeScript)
            return
        }
        end("another")
        guard let window = Self.window(), let u = MTYouTube.embed(id) else {
            MontanaTrace.mark("youtube", "refused -- no window")
            return
        }
        self.id = id
        let w = Self.webView(self)
        web = w
        let host = Self.host(in: window)
        let s = stage(w, in: host)
        stage = s
        host.addSubview(s)
        s.alpha = 0
        UIView.animate(withDuration: 0.2) { s.alpha = 1 }
        var q = URLRequest(url: u)
        q.setValue(MTYouTube.referer, forHTTPHeaderField: "Referer")
        w.load(q)
        MontanaTrace.mark("youtube", "open")
    }

    /// The system's own full-screen player; a page that gives none is opened by YouTube itself.
    private func enlarge() {
        web?.evaluateJavaScript(Self.wholeScript) { [weak self] said, _ in
            let word = (said as? String) ?? "no answer"
            MontanaTrace.mark("youtube", "full screen " + word)
            guard word != "asked", word != "entered" else { return }
            self?.leave()
        }
    }
    /// A sound of ours starts, or the app leaves the screen: the video rests where it stands.
    func rest() {
        guard let w = web else { return }
        w.evaluateJavaScript(Self.pauseScript)
        quiet()
    }
    /// The player is silent: its hold on the sound goes, and the last of ours to let go lowers the session -- another app plays on.
    private func quiet() {
        guard MTYouTube.sounds else { return }
        MTYouTube.sounds = false
        MontanaAudioSession.release(Self.hold)
    }
    /// The player ends: its sound let go, its page emptied, our mini player away.
    func end(_ why: String) {
        guard let w = web else { return }
        MontanaTrace.mark("youtube", "end " + why)
        quiet()
        w.stopLoading()
        w.configuration.userContentController.removeScriptMessageHandler(forName: Self.channel)
        w.loadHTMLString("", baseURL: nil)
        web = nil
        id = nil
        whole = false
        let s = stage
        stage = nil
        UIView.animate(withDuration: 0.2, animations: { s?.alpha = 0 }) { _ in s?.removeFromSuperview() }
    }
    /// The video leaves for YouTube itself, and our player ends: the last way where the system gives the page no player of its own.
    private func leave() {
        guard let id, let u = MTYouTube.watch(id) else { return }
        MontanaTrace.mark("youtube", "leave to the service by=no-player")
        end("leave")
        UIApplication.shared.open(u)
    }

    private func show() {
        guard let s = stage else { return }
        s.superview?.bringSubviewToFront(s)
        s.isUserInteractionEnabled = true
        UIView.animate(withDuration: 0.2) { s.alpha = 1 }
    }
    private func tuck() {
        guard let s = stage else { return }
        s.isUserInteractionEnabled = false
        UIView.animate(withDuration: 0.2) { s.alpha = 0 }
    }
    @objc private func closeTapped() { end("closed by the person") }
    @objc private func wholeTapped() { MontanaTrace.mark("youtube", "full screen by the person"); enlarge() }
    /// The bar carries the window under the finger; the release sets it into the nearest corner of the screen's safe area.
    @objc private func dragged(_ g: UIPanGestureRecognizer) {
        guard let s = stage, let host = s.superview else { return }
        let d = g.translation(in: host)
        g.setTranslation(.zero, in: host)
        s.center = CGPoint(x: s.center.x + d.x, y: s.center.y + d.y)
        guard g.state == .ended || g.state == .cancelled else { return }
        let safe = host.bounds.inset(by: host.safeAreaInsets).insetBy(dx: 12, dy: 12)
        let left = s.center.x < host.bounds.midX, top = s.center.y < host.bounds.midY
        let x = left ? safe.minX + s.bounds.width / 2 : safe.maxX - s.bounds.width / 2
        let y = top ? safe.minY + s.bounds.height / 2 : safe.maxY - s.bounds.height / 2
        UIView.animate(withDuration: 0.25, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0, options: [],
                       animations: { s.center = CGPoint(x: x, y: y) })
    }

    func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let said = message.body as? String, message.webView === web else { return }
        MontanaTrace.mark("youtube", "player " + said)
        if said == "playing" {
            MTYouTube.sounds = true
            let v = VoicePlayer.shared
            if v.playingFile != nil, !v.paused { v.pause() }   // one sound: our own track rests while YouTube plays
            if MontanaVideoDock.shared.file != nil { MontanaVideoDock.shared.close() }
            MontanaAudioSession.activatePlayback(Self.hold)
        } else if ["pause", "ended", "error"].contains(said) {
            quiet()
        }
        if said.hasPrefix("mode") { MontanaTrace.mark("youtube", "windows " + Self.windowsLine()) }
        if said.hasPrefix("mode fullscreen") {
            whole = true
            tuck()
        } else if said.hasPrefix("mode inline"), whole {
            whole = false   // the system player's Done: the video comes back into our mini player and plays on there
            show()
        }
    }
    /// A link inside the player (the title, the logo, «Watch on YouTube») goes to YouTube itself.
    func webView(_ w: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        let away = action.targetFrame == nil ? true : action.navigationType == .linkActivated
        if away, let u = action.request.url, ["https", "http"].contains(u.scheme ?? "") {
            MontanaTrace.mark("youtube", "leave to the service by=player")
            UIApplication.shared.open(u)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    /// THE MINI PLAYER STANDS IN THE APP'S OWN HIERARCHY: in the view of the window's root controller, which is never dismissed, so
    /// it outlives a page or a sheet closing and the web view's responder chain names a controller; every change of the player's mode
    /// names the scene's windows in the diary, by kind and level alone.
    private static func host(in window: UIWindow) -> UIView { window.rootViewController?.view ?? window }
    private static func windowsLine() -> String {
        let scenes = UIApplication.shared.connectedScenes.compactMap { s in s as? UIWindowScene }
        var out: [String] = []
        for w in scenes.flatMap({ s in s.windows }) {
            var line = String(describing: type(of: w)) + "@" + String(Int(w.windowLevel.rawValue))
            if w.isHidden { line += ":hidden" }
            if w.isKeyWindow { line += ":key" }
            if !w.isUserInteractionEnabled { line += ":untouched" }
            line += ":a" + String(format: "%.1f", Double(w.alpha))
            out.append(line)
        }
        return out.joined(separator: ",")
    }
    private static func window() -> UIWindow? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { s in s as? UIWindowScene }
        let live = scenes.first { s in s.activationState == .foregroundActive } ?? scenes.first
        return live?.windows.first { w in w.isKeyWindow } ?? live?.windows.first
    }
    private static func webView(_ watch: MTYouTubeStage) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.allowsInlineMediaPlayback = true
        cfg.mediaTypesRequiringUserActionForPlayback = []   // the person's tap was the action: the video starts at once
        cfg.allowsPictureInPictureMediaPlayback = false     // our mini player is the window (the author's word 18.10.2026 08:1x UTC)
        cfg.websiteDataStore = .nonPersistent()
        cfg.userContentController.add(watch, name: channel)
        cfg.userContentController.addUserScript(WKUserScript(source: listen, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        let v = WKWebView(frame: .zero, configuration: cfg)
        v.isOpaque = false
        v.backgroundColor = .black
        v.scrollView.isScrollEnabled = false
        v.scrollView.contentInsetAdjustmentBehavior = .never
        v.navigationDelegate = watch
        return v
    }
    /// Our mini player: YouTube's own player and nothing of ours over it -- 200 points tall, the least YouTube's policies allow, as
    /// wide as the video's proportion within the screen -- and our bar under it, at the bottom corner above the home indicator,
    /// rounded as the system's windows are. The player takes the finger by design: its own controls are YouTube's.
    private func stage(_ w: WKWebView, in host: UIView) -> UIView {
        let tall = Self.tall, bar = Self.bar
        let wide = min(host.bounds.width - 24, (tall * 16 / 9).rounded())
        let safe = host.bounds.inset(by: host.safeAreaInsets)
        let s = UIView(frame: CGRect(x: safe.maxX - wide - 12, y: safe.maxY - tall - bar - 12, width: wide, height: tall + bar))
        s.backgroundColor = .black
        s.layer.cornerRadius = 12
        s.layer.cornerCurve = .continuous
        s.clipsToBounds = true
        w.frame = CGRect(x: 0, y: 0, width: wide, height: tall)
        s.addSubview(w)
        let strip = UIVisualEffectView(effect: UIBlurEffect(style: .systemThickMaterial))
        strip.frame = CGRect(x: 0, y: tall, width: wide, height: bar)
        let full = Self.mark("arrow.up.left.and.arrow.down.right", label: String(localized: "Full Screen", bundle: MTLanguage.bundle))
        let close = Self.mark("xmark", label: String(localized: "Close", bundle: MTLanguage.bundle))
        full.frame = CGRect(x: 4, y: 0, width: bar, height: bar)
        close.frame = CGRect(x: wide - bar - 4, y: 0, width: bar, height: bar)
        full.addTarget(self, action: #selector(wholeTapped), for: .touchUpInside)
        close.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        strip.contentView.addSubview(full)
        strip.contentView.addSubview(close)
        strip.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(dragged(_:))))
        s.addSubview(strip)
        return s
    }
    private static func mark(_ symbol: String, label: String) -> UIButton {
        let b = UIButton(type: .system)
        b.setImage(UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(textStyle: .body, scale: .medium)), for: .normal)
        b.tintColor = .label
        b.accessibilityLabel = label
        return b
    }
}
