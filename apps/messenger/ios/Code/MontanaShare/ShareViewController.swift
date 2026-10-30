import UIKit
import AVFoundation
import UniformTypeIdentifiers
import Intents
import ImageIO
import UserNotifications

// Montana share extension -- choosing who receives what is being shared.
// The platform's own sheet, dark, on the platform's glass as the big player is: a search, a grid of round faces and, once the
// finger chose a chat, the caption and the send. ONLY THE FINGER CHOOSES AND ONLY THE FINGER SENDS (T1 30.09 04:15:44Z: a file
// went to a chat the finger never chose -- the system's suggestion sent at once): a send is born by the send button alone.
// The extension seals and files the content-addressed pieces itself and records the share in the sender's chat BEFORE any
// network step; the app, when opened, sends whatever the sheet could not.
// One's own wall is the first circle: it opens the post's page with all that is shared, and the app makes the post.

final class ShareViewController: UIViewController {
    private var shown = false
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.25)
    }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !shown else { return }; shown = true
        let picker = SharePickerController()
        picker.attachments = (extensionContext?.inputItems as? [NSExtensionItem])?
            .flatMap { $0.attachments ?? [] } ?? []
        picker.chats = ShareChat.mirror()
        // THE SYSTEM'S SUGGESTION IS A FACT FOR THE DIARY, NEVER A CHOICE: whether the system handed one, and whether the list
        // knows its chat -- the next "it went to someone" is read from these lines.
        if let named = (extensionContext?.intent as? INSendMessageIntent)?.conversationIdentifier, !named.isEmpty {
            let c = MTNoticeAlias.open(named)   // the system offered the chat under this phone's alias (MontanaNotify.suggest)
            let known = picker.chats.contains { $0.name == c } ? 1 : 0
            ShareSend.diag("sheet intent chat=\(String(c.prefix(10))) known=\(known) -- the finger picks")
        } else {
            ShareSend.diag("sheet intent none")
        }
        picker.onClose = { [weak self] in
            self?.dismiss(animated: true) {
                self?.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
            }
        }
        let nav = UINavigationController(rootViewController: picker)
        nav.modalPresentationStyle = .pageSheet
        nav.overrideUserInterfaceStyle = .dark   // the big player's own look
        nav.view.backgroundColor = .clear        // each page lays its own glass
        if let sheet = nav.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
        nav.presentationController?.delegate = picker
        present(nav, animated: true)
    }
}

struct ShareChat {
    let name: String       // the reference this goes to (conv id)
    let title: String
    let initial: String
    let colorHex: String
    let thumb: UIImage?

    /// THE PERSON'S OWN WALL, THE FIRST CIRCLE (the author's word 29.09: "through the share menu I write on my own wall -- the
    /// first circle"). Not a chat and never a letter's address: its name is the sheet's own word; its face is the one the Saved
    /// Messages row wears -- one's own (the author's word 11.09).
    static let wallName = "montana.wall.mine"
    static func wall(from chats: [ShareChat]) -> ShareChat {
        let me = chats.first { $0.name == savedMessagesKey }
        let title = String(localized: "My wall", bundle: MTLanguage.bundle)
        return ShareChat(name: wallName, title: title, initial: me?.initial ?? MontanaAvatar.initial(title: title, name: ""),
                         colorHex: me?.colorHex ?? MontanaAvatar.colorHex(wallName), thumb: me?.thumb)
    }

    /// The chats the app mirrors for the sheet (MontanaChatStore.mirrorChatsToShare): the rendered list, its order.
    static func mirror() -> [ShareChat] {
        guard let d = MontanaKeychain.get("shareChats"),
              let arr = (try? JSONSerialization.jsonObject(with: d)) as? [[String: String]] else { return [] }
        return arr.map { m in
            var img: UIImage?
            if let t = m["thumb"], let data = Data(base64Encoded: t) { img = UIImage(data: data) }
            return ShareChat(name: m["name"] ?? "", title: m["title"] ?? (m["name"] ?? ""),
                             initial: m["initial"] ?? "?", colorHex: m["colorHex"] ?? "#30B0C7", thumb: img)
        }.filter { !$0.name.isEmpty }
    }
}

/// The sheet's glass, from the one owner of the platform's glass (MTGlassKit): the ground of each page, the plates under its
/// controls, the bar that lets the page's glass through, the one prominent button of a page and the cross.
enum ShareGlass {
    static func lay(_ v: UIView, corner: CGFloat) {
        let g = MTGlassKit.plate(corner: corner)
        g.translatesAutoresizingMaskIntoConstraints = false
        v.insertSubview(g, at: 0)
        NSLayoutConstraint.activate([
            g.topAnchor.constraint(equalTo: v.topAnchor), g.bottomAnchor.constraint(equalTo: v.bottomAnchor),
            g.leadingAnchor.constraint(equalTo: v.leadingAnchor), g.trailingAnchor.constraint(equalTo: v.trailingAnchor),
        ])
    }
    static func clearBar(_ item: UINavigationItem) {
        let look = UINavigationBarAppearance()
        look.configureWithTransparentBackground()
        item.standardAppearance = look
        item.scrollEdgeAppearance = look
        item.compactAppearance = look
    }
    /// OUR SEND, NOT THE PLATFORM'S WHITE PLATE (the author's word 16.10.2026 16:0x UTC on T1: «on the share page the button is not
    /// seen -- white, not our send»): the chat's own mark (MTComposeMark .send), the author's file SendButton byte for byte -- the
    /// sheet's own catalog (ShareAssets.xcassets) holds a copy of the app's protected file, held equal to it by the guard (P-118.10)
    /// -- drawn whole at the bar's height, a 44-point target.
    static func send(label: String) -> UIButton {
        let b = UIButton(type: .custom)
        b.setImage(UIImage(named: "SendButton"), for: .normal)
        b.imageView?.contentMode = .scaleAspectFit
        b.contentHorizontalAlignment = .fill
        b.contentVerticalAlignment = .fill
        b.accessibilityLabel = label
        b.translatesAutoresizingMaskIntoConstraints = false
        return b
    }
    /// The cross that takes a thing off: the platform's glyph, readable on any picture, inside the finger's 44 points.
    static func cross(_ label: String, _ act: @escaping () -> Void) -> UIButton {
        let b = UIButton(type: .system)
        let look = UIImage.SymbolConfiguration(pointSize: 22)
            .applying(UIImage.SymbolConfiguration(paletteColors: [.white, UIColor.black.withAlphaComponent(0.55)]))
        b.setImage(UIImage(systemName: "xmark.circle.fill", withConfiguration: look), for: .normal)
        b.accessibilityLabel = label
        b.addAction(UIAction { _ in act() }, for: .primaryActionTriggered)
        b.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([b.widthAnchor.constraint(equalToConstant: 44), b.heightAnchor.constraint(equalToConstant: 44)])
        return b
    }
}

final class SharePickerController: UIViewController, UICollectionViewDataSource,
        UICollectionViewDelegate, UITextFieldDelegate, UITextViewDelegate,
        UIAdaptivePresentationControllerDelegate {

    var attachments: [NSItemProvider] = []
    var onClose: (() -> Void)?
    var chats: [ShareChat] = []

    private var all: [ShareChat] = []
    private var shown: [ShareChat] = []
    private var selected: [String] = []           // the chats the finger chose, in the order it chose them
    private var selectedSet = Set([String]())
    private var sends = [String: ShareAvatarCell.Send]()   // the chosen faces' circles while a send is on its way (17.10)

    private let search = UITextField()
    private var collection: UICollectionView!
    private let bar = UIView()                    // the caption and the send: they stand once the finger chose a chat
    private let caption = UITextView()
    private let captionPlaceholder = UILabel()
    private lazy var sendButton = ShareGlass.send(label: String(localized: "Send", bundle: MTLanguage.bundle))
    private let road = UIView()                   // a send on its way, where the bar stood
    private let progress = UIProgressView(progressViewStyle: .bar)
    private let status = UILabel()
    private let emptyLabel = UILabel()
    private var captionHeight: NSLayoutConstraint!

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        ShareGlass.lay(view, corner: 0)
        title = String(localized: "Send to Montana", bundle: MTLanguage.bundle)
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .close, target: self, action: #selector(cancelTap))
        navigationItem.backButtonDisplayMode = .minimal   // the post's page goes back by the chevron alone
        ShareGlass.clearBar(navigationItem)
        all = [ShareChat.wall(from: chats)] + chats   // one's own wall is the first circle (the author's word 29.09)
        ShareSend.diag("sheet ORDER n=\(chats.count) order=\(MTShareOrder.print(chats.map(\.name)))")
        shown = all
        buildUI()
    }

    // -- UI --
    private func buildUI() {
        let searchPlate = UIView()
        searchPlate.translatesAutoresizingMaskIntoConstraints = false
        ShareGlass.lay(searchPlate, corner: 22)
        search.placeholder = String(localized: "Search", bundle: MTLanguage.bundle)
        search.font = .systemFont(ofSize: 17)
        search.autocorrectionType = .no
        search.returnKeyType = .search
        search.clearButtonMode = .whileEditing
        search.delegate = self
        search.addTarget(self, action: #selector(searchChanged), for: .editingChanged)
        let glass = UIImageView(image: UIImage(systemName: "magnifyingglass"))
        glass.tintColor = .secondaryLabel
        glass.contentMode = .center
        let lv = UIView(frame: CGRect(x: 0, y: 0, width: 38, height: 44)); lv.addSubview(glass)
        glass.frame = CGRect(x: 12, y: 12, width: 20, height: 20)
        search.leftView = lv; search.leftViewMode = .always
        search.translatesAutoresizingMaskIntoConstraints = false
        searchPlate.addSubview(search)

        let layout = UICollectionViewFlowLayout()
        layout.minimumInteritemSpacing = 0
        layout.minimumLineSpacing = 4
        collection = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collection.backgroundColor = .clear
        collection.alwaysBounceVertical = true
        collection.keyboardDismissMode = .onDrag
        collection.dataSource = self
        collection.delegate = self
        collection.register(ShareAvatarCell.self, forCellWithReuseIdentifier: "c")
        collection.translatesAutoresizingMaskIntoConstraints = false

        emptyLabel.text = String(localized: "No active chats.\nOpen Montana and start a conversation.", bundle: MTLanguage.bundle)
        emptyLabel.numberOfLines = 0
        emptyLabel.textAlignment = .center
        emptyLabel.textColor = .secondaryLabel
        emptyLabel.font = .systemFont(ofSize: 15)
        emptyLabel.isHidden = !chats.isEmpty
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false

        // THE BAR FLOATS ON ITS OWN GLASS OVER THE GRID, as the big player's plate does: the caption and, beside it, the send.
        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.isHidden = true
        let capPlate = UIView()
        capPlate.translatesAutoresizingMaskIntoConstraints = false
        ShareGlass.lay(capPlate, corner: 22)
        caption.font = .systemFont(ofSize: 17)
        caption.backgroundColor = .clear
        caption.textContainerInset = UIEdgeInsets(top: 12, left: 10, bottom: 12, right: 10)
        caption.isScrollEnabled = false
        caption.delegate = self
        caption.translatesAutoresizingMaskIntoConstraints = false
        captionPlaceholder.text = String(localized: "Add a caption…", bundle: MTLanguage.bundle)
        captionPlaceholder.font = .systemFont(ofSize: 17)
        captionPlaceholder.textColor = .placeholderText
        captionPlaceholder.translatesAutoresizingMaskIntoConstraints = false
        caption.addSubview(captionPlaceholder)
        capPlate.addSubview(caption)
        sendButton.addTarget(self, action: #selector(sendTap), for: .primaryActionTriggered)
        [capPlate, sendButton].forEach { bar.addSubview($0) }

        road.translatesAutoresizingMaskIntoConstraints = false
        road.isHidden = true
        ShareGlass.lay(road, corner: 22)
        progress.translatesAutoresizingMaskIntoConstraints = false
        progress.progressTintColor = .systemBlue   // the platform's own blue (the author's word 30.09 23:21)
        progress.isHidden = true   // the send fills the faces' circles now (ShareRing, 17.10); the road keeps its words
        status.font = .systemFont(ofSize: 15, weight: .medium)
        status.textColor = .label
        status.numberOfLines = 2
        status.translatesAutoresizingMaskIntoConstraints = false
        [status, progress].forEach { road.addSubview($0) }

        [searchPlate, collection, emptyLabel, bar, road].forEach { view.addSubview($0) }
        captionHeight = caption.heightAnchor.constraint(equalToConstant: 44)

        NSLayoutConstraint.activate([
            searchPlate.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            searchPlate.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            searchPlate.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            searchPlate.heightAnchor.constraint(equalToConstant: 44),
            search.topAnchor.constraint(equalTo: searchPlate.topAnchor),
            search.bottomAnchor.constraint(equalTo: searchPlate.bottomAnchor),
            search.leadingAnchor.constraint(equalTo: searchPlate.leadingAnchor),
            search.trailingAnchor.constraint(equalTo: searchPlate.trailingAnchor, constant: -8),

            collection.topAnchor.constraint(equalTo: searchPlate.bottomAnchor, constant: 8),
            collection.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collection.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collection.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            emptyLabel.topAnchor.constraint(equalTo: collection.topAnchor, constant: 150),
            emptyLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            emptyLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),

            bar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            bar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            // THE BAR STANDS ON THE KEYS BY THE PLATFORM'S OWN GUIDE (T1 16.10.2026: the send was not seen): the sum of the keys'
            // frame by hand, in the coordinates of a sheet that moves itself over the keys, put the bar under the sheet's edge; the
            // keyboard layout guide is the safe area's bottom with no keys and the keys' top with them, in any detent.
            bar.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor, constant: -10),
            capPlate.topAnchor.constraint(equalTo: bar.topAnchor),
            capPlate.bottomAnchor.constraint(equalTo: bar.bottomAnchor),
            capPlate.leadingAnchor.constraint(equalTo: bar.leadingAnchor),
            capPlate.trailingAnchor.constraint(equalTo: sendButton.leadingAnchor, constant: -8),
            caption.topAnchor.constraint(equalTo: capPlate.topAnchor),
            caption.bottomAnchor.constraint(equalTo: capPlate.bottomAnchor),
            caption.leadingAnchor.constraint(equalTo: capPlate.leadingAnchor),
            caption.trailingAnchor.constraint(equalTo: capPlate.trailingAnchor),
            captionHeight,
            captionPlaceholder.leadingAnchor.constraint(equalTo: caption.leadingAnchor, constant: 14),
            captionPlaceholder.topAnchor.constraint(equalTo: caption.topAnchor, constant: 12),
            sendButton.trailingAnchor.constraint(equalTo: bar.trailingAnchor),
            sendButton.bottomAnchor.constraint(equalTo: bar.bottomAnchor),
            sendButton.widthAnchor.constraint(equalToConstant: 44),
            sendButton.heightAnchor.constraint(equalToConstant: 44),

            road.leadingAnchor.constraint(equalTo: bar.leadingAnchor),
            road.trailingAnchor.constraint(equalTo: bar.trailingAnchor),
            road.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor, constant: -10),
            status.topAnchor.constraint(equalTo: road.topAnchor, constant: 12),
            status.leadingAnchor.constraint(equalTo: road.leadingAnchor, constant: 16),
            status.trailingAnchor.constraint(equalTo: road.trailingAnchor, constant: -16),
            progress.topAnchor.constraint(equalTo: status.bottomAnchor, constant: 10),
            progress.leadingAnchor.constraint(equalTo: road.leadingAnchor, constant: 16),
            progress.trailingAnchor.constraint(equalTo: road.trailingAnchor, constant: -16),
            progress.bottomAnchor.constraint(equalTo: road.bottomAnchor, constant: -14),
        ])
    }

    // -- the grid --
    func collectionView(_ cv: UICollectionView, numberOfItemsInSection s: Int) -> Int { shown.count }
    func collectionView(_ cv: UICollectionView, cellForItemAt ip: IndexPath) -> UICollectionViewCell {
        let cell = cv.dequeueReusableCell(withReuseIdentifier: "c", for: ip) as! ShareAvatarCell
        let c = shown[ip.row]
        cell.configure(c, selected: selectedSet.contains(c.name), send: sends[c.name])
        return cell
    }
    /// The circles of the faces on the screen, from the send's one record -- moved, not drawn anew.
    private func paintSends(animated: Bool) {
        for case let cell as ShareAvatarCell in collection.visibleCells {
            guard let ip = collection.indexPath(for: cell), ip.row < shown.count else { continue }
            let name = shown[ip.row].name
            cell.show(selected: selectedSet.contains(name), send: sends[name], animated: animated)
        }
    }
    /// The circles fill by the network's truth -- a piece counts once it is on the node -- up to nine tenths; the rest is the
    /// letter's, which only the node's acceptance of that chat's letters closes.
    @MainActor private func fill(_ fraction: Double) {
        let f = 0.9 * max(0, min(1, fraction))
        for (peer, s) in sends where s != .sent { sends[peer] = .sending(f) }
        paintSends(animated: true)
    }
    func collectionView(_ cv: UICollectionView, didSelectItemAt ip: IndexPath) {
        let name = shown[ip.row].name
        // THE WALL IS WRITTEN ON, NEVER SENT TO (the author's word 30.09): its circle opens the post's page and chooses nothing.
        if name == ShareChat.wallName { openWall(); return }
        if selectedSet.contains(name) { selectedSet.remove(name); selected.removeAll { $0 == name } }
        else { selectedSet.insert(name); selected.append(name) }
        cv.reloadItems(at: [ip])
        updateSendState()
    }
    func numberOfSections(in cv: UICollectionView) -> Int { 1 }

    /// THE WALL'S CIRCLE HANDS THE SHARE TO THE APP'S ONE NEW-POST PAGE (the author's word 02.10 19:17: «sharing onto the wall
    /// through Share must open the same publishing function with all its capabilities»). The sheet's own post page was a
    /// reduced copy of the wall's -- no more pictures, no file picked, no frame, no draft kept. The sheet now reads what was
    /// shared once, lays it as one record and goes (ShareWallHandoff); the app lays it into my wall's draft and opens the wall's
    /// own page over it (MTBoard.takeFromSheet). A running app takes it at once by the ring; a sleeping one when it next comes
    /// to the screen -- no public word of the platform lets a share sheet bring its app forward.
    private var handing = false
    private func openWall() {
        guard !handing else { return }
        handing = true
        view.endEditing(true)
        bar.isHidden = true
        road.isHidden = false
        collection.isUserInteractionEnabled = false
        search.isEnabled = false
        status.text = String(localized: "Preparing", bundle: MTLanguage.bundle)
        ShareSend.diag("sheet WALL hand items=\(attachments.count)")
        let items = attachments
        Task { @MainActor [weak self] in
            let laid = await ShareWallHandoff.hand(items)
            if laid {
                ShareSend.ringHost()   // a running app opens the page at once; a sleeping one at its next activation
                await ShareWallHandoff.bell()   // and the person holds the one tap that brings it forward on that page
            }
            self?.onClose?()
        }
    }

    // -- the search --
    @objc private func searchChanged() {
        let q = (search.text ?? "").trimmingCharacters(in: .whitespaces).lowercased()
        shown = q.isEmpty ? all : all.filter { $0.title.lowercased().contains(q) || $0.name.lowercased().contains(q) }
        collection.reloadData()
    }
    func textFieldShouldReturn(_ tf: UITextField) -> Bool { tf.resignFirstResponder(); return true }

    // -- the caption --
    func textViewDidChange(_ tv: UITextView) {
        captionPlaceholder.isHidden = !tv.text.isEmpty
        let fits = tv.sizeThatFits(CGSize(width: tv.bounds.width, height: .infinity)).height
        captionHeight.constant = min(120, max(44, fits))
        tv.isScrollEnabled = 120 < fits   // words past the field's height scroll inside it, never under its edge
    }

    private func updateSendState() {
        let chosen = !selected.isEmpty
        bar.isHidden = !chosen
        collection.contentInset.bottom = chosen ? 72 : 0
    }

    // -- sending --
    /// Where the sheet stands (the author's word 16.09: the diary must say where a sheet died).
    private var stage = "idle" { didSet { ShareSend.diag("sheet STAGE \(stage)") } }
    private var hostWatched = false
    private func watchHost() {
        guard !hostWatched else { return }; hostWatched = true
        NotificationCenter.default.addObserver(forName: NSNotification.Name.NSExtensionHostWillResignActive, object: nil, queue: .main) { [weak self] _ in
            ShareSend.diag("sheet HOST resigned stage=\(self?.stage ?? "?")")
        }
        NotificationCenter.default.addObserver(forName: NSNotification.Name.NSExtensionHostDidEnterBackground, object: nil, queue: .main) { [weak self] _ in
            ShareSend.diag("sheet HOST background stage=\(self?.stage ?? "?")")
        }
    }
    @objc private func cancelTap() { ShareSend.diag("sheet CANCEL by hand stage=\(stage)"); onClose?() }
    func presentationControllerDidDismiss(_ pc: UIPresentationController) { ShareSend.diag("sheet DISMISSED by hand stage=\(stage)"); onClose?() }

    // One drawing for both stages, compression and sending: the platform's bar moves smoothly, its words change only on whole
    // per cents -- updating them on every piece made them flicker.
    private var lastShownPct = -1
    private var lastStage = ""
    private var batchIndex = 0
    private var batchTotal = 0

    @MainActor
    func showStage(_ stage: String, _ fraction: Double, detail: String = "") {
        let f = max(0, min(1, fraction))
        let stageKey = stage + "#" + String(batchIndex)
        if stageKey != lastStage { lastStage = stageKey; lastShownPct = -1; progress.setProgress(0, animated: false) }
        progress.setProgress(Float(f), animated: true)
        let pct = Int(f * 100)
        guard pct != lastShownPct else { return }
        lastShownPct = pct
        // On a batch the item number is shown too: otherwise the bar simply jumps from the end back to the start and looks broken.
        let prefix = batchTotal > 1 ? "\(batchIndex)/\(batchTotal)  " : ""
        status.text = prefix + (detail.isEmpty ? "\(stage)  \(pct)%" : "\(stage)  \(pct)%   \(detail)")
    }

    @objc private func sendTap() { beginSend() }

    // THE ONE BIRTH OF A SEND: the finger on the send button, to the chats the finger chose -- never the system's suggestion, a
    // last correspondent or a default (T1 30.09 04:15:44Z: a file went where the finger never pointed).
    private func beginSend() {
        let peers = selected
        guard !peers.isEmpty else { return }
        view.endEditing(true)
        let caps = caption.text ?? ""
        bar.isHidden = true
        road.isHidden = false
        collection.isUserInteractionEnabled = false
        search.isEnabled = false
        status.text = String(localized: "Sending…", bundle: MTLanguage.bundle)
        for peer in peers { sends[peer] = .waiting }
        paintSends(animated: false)
        ShareSend.diag("sheet SEND tapped items=\(attachments.count) peers=\(peers.count)")
        watchHost(); stage = "prepare"
        Task { ShareSend.diag("sheet NET " + (await ShareSend.netEnv())) }   // the sheet's own path, at the tap
        // A share that carries a WEB LINK is a link. App Store (and its kin) hand the icon as a SECOND attachment beside the URL:
        // the icon rode ahead as a broken "Photo" bubble while the link followed (28.08). Companion previews are dressing, not
        // content -- only the link and its text travel.
        let urlT = UTType.url.identifier, fileT = UTType.fileURL.identifier, textT = UTType.plainText.identifier
        let hasWebLink = attachments.contains {
            $0.hasItemConformingToTypeIdentifier(urlT) && !$0.hasItemConformingToTypeIdentifier(fileT)
        }
        let toProcess = hasWebLink
            ? attachments.filter { $0.hasItemConformingToTypeIdentifier(urlT) || $0.hasItemConformingToTypeIdentifier(textT) }
            : attachments
        Task {
            await ShareSend.judgeDoors()   // the doors of THIS network, judged now -- one behaviour on any network (16.09)
            var items: [[String: Any]] = []
            // Strictly one at a time. Starting every item at once, under a memory limit of about 120 MB, loses the whole batch to
            // a single failure. A sequence gives order, bounded memory and isolation: the item that fails is skipped.
            let total = toProcess.count
            for (idx, p) in toProcess.enumerated() {
                await MainActor.run { self.batchIndex = idx + 1; self.batchTotal = total }
                // Every item leaves a line BEFORE it is worked on: a sheet that dies mid-item then names the item it died on.
                ShareSend.diag("sheet ITEM \(idx + 1)/\(total) types=\(p.registeredTypeIdentifiers.prefix(3).joined(separator: ","))")
                if let rec = await self.processOne(p) { items.append(rec) }
            }
            // THE SENDER'S CHAT FIRST -- BEFORE ANY NETWORK STEP (the author's word 29.08, made true 17.09, the critic): every
            // prepared item is recorded NOW under its name, uploaded=false, sent=false, and the app is rung. A dead network, a
            // failed upload, a sheet killed mid-way: the row stands in the sender's chat and the app's ONE engine finishes the
            // road from the shelf. ONE GROUP FOR THE PICTURES SHARED TOGETHER (the author's word 20.09): the same owner mints the
            // key and stamps the letters (MTMediaGroup); a file or a text between them is no member and folds nothing.
            var captionCarried = false
            var lettered: [[String: Any]] = []
            let foldable = items.filter { ($0["kind"] as? String) == "img" || ($0["kind"] as? String) == "vid" }.count
            let slots = MTMediaGroup.slots(foldable)
            var placed = 0
            for var item in items {
                if var m = item["manifest"] as? [String: Any] {
                    if !caps.isEmpty, !captionCarried { m["cap"] = caps; captionCarried = true }
                    if let kind = item["kind"] as? String, kind == "img" || kind == "vid" {
                        if let g = slots[placed] { MTMediaGroup.stamp(&m, g) }
                        placed += 1
                    }
                    item["manifest"] = m
                    item["uploaded"] = false
                }
                lettered.append(item)
            }
            if lettered.count > 1 { ShareSend.diag("sheet GROUP n=\(foldable) of=\(lettered.count) key=\(String((slots.first??.key ?? "-").prefix(8)))") }
            // THE ORDER RIDES IN THE NAMES (the author's word 18.10.2026 07:2x UTC: «the order of the messages broke, and it must be
            // strictly as I sent them»): a receiver orders letters by the birth the name carries (ChatStore.birthMs), and a bare
            // UUID carries none -- a big video that came last stood first. Each item is born a millisecond after the one before, in
            // the order the person chose them, under the app's own form of a name (ChatStore.mintMid: «t» + ms + «-» + a UUID).
            var batch: [[String: Any]] = []
            var born = Int64(Date().timeIntervalSince1970 * 1000)
            for peer in peers {
                let title = all.first { $0.name == peer }?.title ?? peer
                var items0: [[String: Any]] = []
                for var item in lettered {
                    item["mid"] = "t" + String(born) + "-" + UUID().uuidString
                    born += 1
                    item["sent"] = false
                    items0.append(item)
                }
                // WHOSE HAND THE SHARE IS IN (20.09, the critic): born in the sheet's hand; the app takes it only when the sheet
                // has passed it (below, after the last flag), or when the sheet is dead (a record older than its lease).
                batch.append(["peer": peer, "title": title,
                              "caption": captionCarried ? "" : caps, "items": items0,
                              "owner": "sheet", "born": Date().timeIntervalSince1970])
            }
            var pending: [[String: Any]] = []
            if let d = MontanaKeychain.get("pendingShare"),
               let arr = (try? JSONSerialization.jsonObject(with: d)) as? [[String: Any]] { pending = arr }
            pending.append(contentsOf: batch)
            if let d = try? JSONSerialization.data(withJSONObject: pending) { MontanaKeychain.set("pendingShare", d) }
            ShareSend.diag("sheet SAVED items=\(lettered.count) peers=\(peers.count)")
            // THEN THE NETWORK. The pieces go to the node from HERE, once per item. "Sending" is network truth: the bar moves only
            // when a piece is on the node. An item whose upload fails keeps uploaded=false and gets no letter; the app re-sends it
            // from the shelf on its own road (share_resend). The sheet never buys delivery with a hang and never drops the item.
            await MainActor.run { self.stage = "upload" }
            var uploadedAt: [Bool] = Array(repeating: false, count: lettered.count)
            var failed = 0
            let pieces = lettered.count
            for (idx, item) in lettered.enumerated() {
                await MainActor.run { self.batchIndex = idx + 1; self.batchTotal = lettered.count }
                guard let m = item["manifest"] as? [String: Any] else { uploadedAt[idx] = true; continue }   // a text has no pieces
                let ok = await ShareSend.uploadManifestChunks(m) { done, totalChunks in
                    Task { @MainActor in
                        self.showStage(String(localized: "Sending", bundle: MTLanguage.bundle), Double(done) / Double(max(1, totalChunks)))
                        self.fill((Double(idx) + Double(done) / Double(max(1, totalChunks))) / Double(max(1, pieces)))
                    }
                }
                uploadedAt[idx] = ok
                if !ok { failed += 1 }
            }
            await MainActor.run { self.batchIndex = 0; self.batchTotal = 0; self.stage = "letter" }
            // The receiver's leg: the letters of the items whose pieces are on the node ride the node wake, the banner rings now.
            // The app re-sends the SAME mid as the guarantee leg; node and receiver dedup it.
            for bi in batch.indices {
                let peer = (batch[bi]["peer"] as? String) ?? ""
                var items = (batch[bi]["items"] as? [[String: Any]]) ?? []
                for ii in items.indices {
                    var item = items[ii]
                    let mid = (item["mid"] as? String) ?? UUID().uuidString
                    var text = ""
                    if (item["kind"] as? String) == "text" { text = (item["text"] as? String) ?? "" }
                    else if let m = item["manifest"] as? [String: Any] {
                        let up = ii < uploadedAt.count && uploadedAt[ii]
                        item["uploaded"] = up
                        if up, let j = try? JSONSerialization.data(withJSONObject: m) {
                            // ONE decision point from a manifest to its letter ([C-1]): the same MontanaMedia.manifestLetter the chat asks.
                            if let composed = await MontanaMedia.manifestLetter(j, putBlob: {
                                await ShareSend.putBlob($0, data: $1)
                            }) { text = composed.letter }
                            else { ShareSend.diag("letter SKIP manifest mid=\(String(mid.prefix(8)))") }
                        }
                    }
                    if !text.isEmpty { item["letter"] = text }   // composed ONCE: the app's guarantee leg re-sends these very bytes
                    // A GROUP OR A CHANNEL HAS NO PIPE (the author's word 18.10.2026 07:2x UTC: «sharing into a channel failed and hung
                    // with Retry»): its letter is the group's to carry to every member, which the app alone can do (MTGroup) -- the sheet
                    // lays the pieces and the letter and hands the row over.
                    let toGroup = peer.hasPrefix("grp:")
                    item["sent"] = text.isEmpty || toGroup ? false : await ShareSend.sendLetter(peer: peer, mid: mid, text: text)
                    items[ii] = item
                }
                batch[bi]["items"] = items
                let whole = items.allSatisfy { i in (i["sent"] as? Bool) == true }
                await MainActor.run { self.sends[peer] = whole ? .sent : .sending(0.9); self.paintSends(animated: true) }
            }
            // THE HAND PASSES HERE, ONCE: the final flags and the owner are written together, and only then the app is rung.
            // Rows the app already took (a dead-sheet lease that ran out) are left.
            if let d = MontanaKeychain.get("pendingShare"),
               var arr = (try? JSONSerialization.jsonObject(with: d)) as? [[String: Any]] {
                for var row in batch {
                    row["owner"] = "app"
                    let mids = ((row["items"] as? [[String: Any]]) ?? []).compactMap { $0["mid"] as? String }
                    if let idx = arr.firstIndex(where: { r in
                        (r["peer"] as? String) == (row["peer"] as? String) &&
                        ((r["items"] as? [[String: Any]]) ?? []).compactMap({ $0["mid"] as? String }) == mids
                    }) { arr[idx] = row }
                }
                if let d2 = try? JSONSerialization.data(withJSONObject: arr) { MontanaKeychain.set("pendingShare", d2) }
            }
            ShareSend.diag("sheet DONE lettered=\(lettered.count) failed=\(failed)")
            ShareSend.ringHost()   // a running app draws the sender's bubbles NOW, from the finished record
            await MainActor.run { self.stage = "done" }
            if failed > 0 {
                await MainActor.run {
                    self.status.text = String(localized: "Some items are still on their way — Montana will send them.", bundle: MTLanguage.bundle)
                }
                try? await Task.sleep(nanoseconds: 1_800_000_000)
            } else {
                try? await Task.sleep(nanoseconds: 800_000_000)   // the blue «Sent» under each face is seen before the sheet goes
            }
            await MainActor.run { self.onClose?() }
        }
    }

    // -- one attachment: seal and file the pieces into a manifest, or send the text --
    private func processOne(_ p: NSItemProvider) async -> [String: Any]? {
        let movie = UTType.movie.identifier, image = UTType.image.identifier
        let data = UTType.data.identifier, url = UTType.url.identifier, text = UTType.plainText.identifier
        if p.hasItemConformingToTypeIdentifier(movie) {
            // A video in the sheet rides the chat's own road: compressed, both stages visible -- the compression, then the send.
            guard let (srcURL, original) = await ShareRead.fileURL(p, movie) else { return nil }
            defer { try? FileManager.default.removeItem(at: srcURL) }
            await MainActor.run { self.showStage(String(localized: "Compressing", bundle: MTLanguage.bundle), 0) }
            let outURL = await MontanaVideo.compress(srcURL) { pr in
                Task { @MainActor in self.showStage(String(localized: "Compressing", bundle: MTLanguage.bundle), pr) }
            } ?? srcURL
            defer { if outURL != srcURL { try? FileManager.default.removeItem(at: outURL) } }
            let thumb = MontanaMedia.videoPreviewBase64(outURL)
            return await sealFile(outURL, kind: "vid", ext: "mp4", name: original, thumb: thumb)
        }
        // A WEB link goes BEFORE the image and file branches: a provider may wear several faces at once (url + preview image,
        // url + data), and every non-link face turned the link into a broken attachment. Only a FILE url rides the document road.
        if p.hasItemConformingToTypeIdentifier(url),
           !p.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier),
           let s = await ShareRead.text(p, url) { return ["kind": "text", "text": s] }
        // A TEXT IS A TEXT, WHATEVER FACE IT WEARS (13.09, the author's word: a shared link must always arrive as a link).
        if let s = await ShareRead.textFace(p), !s.isEmpty, s.count <= 4500 { return ["kind": "text", "text": s] }
        if p.hasItemConformingToTypeIdentifier(image) {
            // The one shape of a photo on its way out (MontanaMedia.photoForSend): the chat's 1600 px JPEG, never the original --
            // an original decoded whole is what killed the sheet.
            if let (b, _, n) = await ShareRead.file(p, image), let j = MontanaMedia.photoForSend(b) {
                return await seal(j, kind: "img", ext: "jpg", name: n, thumb: MontanaMedia.previewBase64(j))
            }
            if let img = await ShareRead.image(p, image), let raw = img.jpegData(compressionQuality: 0.95),
               let j = MontanaMedia.photoForSend(raw) {
                return await seal(j, kind: "img", ext: "jpg", name: nil, thumb: MontanaMedia.previewBase64(j))
            }
            ShareSend.diag("sheet ITEM image unreadable")
            return nil
        }
        if p.hasItemConformingToTypeIdentifier(data) {
            guard let (b, e, n) = await ShareRead.file(p, data) else { return nil }
            let ex = e.isEmpty ? "bin" : e
            return await seal(b, kind: "doc", ext: ex, name: n, thumb: nil)
        }
        if p.hasItemConformingToTypeIdentifier(text), let s = await ShareRead.text(p, text) { return ["kind": "text", "text": s] }
        return nil
    }

    private func seal(_ file: Data, kind: String, ext: String, name: String?, thumb: String?) async -> [String: Any]? {
        let totalMB = Double(file.count) / 1_048_576.0
        guard let m = await MontanaMedia.buildManifest(
            source: .memory(file), kind: kind, ext: ext, docName: name, thumb: thumb,
            progress: { pr in
                Task { @MainActor in
                    self.showStage(String(localized: "Preparing", bundle: MTLanguage.bundle), pr,
                                   detail: String(format: "%.1f / %.1f MB", pr * totalMB, totalMB))
                }
            }) else { return nil }
        // THE HANDOFF SHELF (17.09): the bytes are laid in the app group for the app to move into its own store -- it used to
        // download its own file back from the node. A shelf that refuses is named aloud (17.09, the critic).
        var item: [String: Any] = ["kind": kind, "manifest": m]
        if let src = MontanaHandoff.lay(file) { item["src"] = src }
        else { ShareSend.diag("shelf REFUSED kind=\(kind) bytes=\(file.count)") }
        return item
    }

    private func sealFile(_ url: URL, kind: String, ext: String, name: String?, thumb: String?) async -> [String: Any]? {
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) as? Int ?? 0
        let totalMB = Double(size) / 1_048_576.0
        guard let m = await MontanaMedia.buildManifest(
            source: .file(url), kind: kind, ext: ext, docName: name, thumb: thumb,
            progress: { pr in
                Task { @MainActor in
                    self.showStage(String(localized: "Preparing", bundle: MTLanguage.bundle), pr,
                                   detail: String(format: "%.1f / %.1f MB", pr * totalMB, totalMB))
                }
            }) else { return nil }
        var item: [String: Any] = ["kind": kind, "manifest": m]
        if let src = MontanaHandoff.lay(file: url) { item["src"] = src }   // the shelf (17.09), see seal()
        else { ShareSend.diag("shelf REFUSED kind=\(kind) bytes=\(size)") }
        return item
    }
}

/// WHAT THE SOURCE HANDED, READ -- one reader for the chats' road and the wall's.
enum ShareRead {
    // ONE rule for the name a shared file wears ([C-1], the author's word 07.09: "the name must be strict"): the name the source
    // gave it -- the provider's suggested name, else the file's own -- never a made-up "file.ext".
    static func originalName(_ p: NSItemProvider, _ u: URL) -> String {
        var name = (p.suggestedName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { name = u.lastPathComponent }
        if (name as NSString).pathExtension.isEmpty, !u.pathExtension.isEmpty { name += "." + u.pathExtension }
        return name
    }
    // The file is put in a temporary folder and worked with by reference: a video is never lifted into memory whole, and an
    // extension has a tighter memory limit than the app.
    static func fileURL(_ p: NSItemProvider, _ t: String) async -> (URL, String)? {
        await withCheckedContinuation { c in
            p.loadFileRepresentation(forTypeIdentifier: t) { u, _ in
                guard let u else { c.resume(returning: nil); return }
                let dst = FileManager.default.temporaryDirectory
                    .appendingPathComponent("shin_\(UUID().uuidString).\(u.pathExtension.isEmpty ? "mov" : u.pathExtension)")
                try? FileManager.default.removeItem(at: dst)
                guard (try? FileManager.default.copyItem(at: u, to: dst)) != nil else { c.resume(returning: nil); return }
                c.resume(returning: (dst, originalName(p, u)))
            }
        }
    }
    static func file(_ p: NSItemProvider, _ t: String) async -> (Data, String, String)? {
        await withCheckedContinuation { c in
            p.loadFileRepresentation(forTypeIdentifier: t) { u, _ in
                guard let u = u, let d = try? Data(contentsOf: u, options: .mappedIfSafe) else { c.resume(returning: nil); return }
                c.resume(returning: (d, u.pathExtension, originalName(p, u)))
            }
        }
    }
    static func image(_ p: NSItemProvider, _ t: String) async -> UIImage? {
        await withCheckedContinuation { c in
            p.loadItem(forTypeIdentifier: t, options: nil) { item, _ in
                if let i = item as? UIImage { c.resume(returning: i) }
                else if let u = item as? URL, let i = UIImage(contentsOfFile: u.path) { c.resume(returning: i) }
                else if let d = item as? Data, let i = UIImage(data: d) { c.resume(returning: i) }
                else { c.resume(returning: nil) }
            }
        }
    }
    /// The text behind a plain-text face or a .txt/.text file; nil for anything else.
    static func textFace(_ p: NSItemProvider) async -> String? {
        if p.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
           let s = await text(p, UTType.plainText.identifier) {
            return s.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard p.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) else { return nil }
        let url: URL? = await withCheckedContinuation { c in
            p.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                if let u = item as? URL { c.resume(returning: u) }
                else if let d = item as? Data, let u = URL(dataRepresentation: d, relativeTo: nil) { c.resume(returning: u) }
                else { c.resume(returning: nil) }
            }
        }
        guard let u = url, ["txt", "text"].contains(u.pathExtension.lowercased()),
              let d = try? Data(contentsOf: u), d.count <= 64_000,
              let s = String(data: d, encoding: .utf8) else { return nil }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    static func text(_ p: NSItemProvider, _ t: String) async -> String? {
        await withCheckedContinuation { c in
            p.loadItem(forTypeIdentifier: t, options: nil) { item, _ in
                if let s = item as? String { c.resume(returning: s) }
                else if let u = item as? URL, !u.isFileURL { c.resume(returning: u.absoluteString) }   // a file's path is never its words: the shared chain (02.10) gave «file:///private/var/...» as the letter
                else if let d = item as? Data, let s = String(data: d, encoding: .utf8) { c.resume(returning: s) }   // some apps hand text as bytes
                else { c.resume(returning: nil) }
            }
        }
    }

    enum WallPart { case words(String), file([String: String]) }
    /// One attachment as a part of a post, in the chats' own order: a video is a file; a web link and a text of bubble size are
    /// words; a picture, then any other file, is a file; a plain text is words.
    static func wallPart(_ p: NSItemProvider) async -> WallPart? {
        let movie = UTType.movie.identifier, image = UTType.image.identifier
        let data = UTType.data.identifier, url = UTType.url.identifier, plain = UTType.plainText.identifier
        if p.hasItemConformingToTypeIdentifier(movie) { return await shelve(p, movie).map { .file($0) } }
        if p.hasItemConformingToTypeIdentifier(url), !p.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier),
           let s = await text(p, url) { return .words(s) }
        if let s = await textFace(p), !s.isEmpty, s.count <= 4500 { return .words(s) }
        if p.hasItemConformingToTypeIdentifier(image) {
            if let f = await shelve(p, image) { return .file(f) }
            // a picture handed only as a picture (a screenshot's editor): its own pixels as a JPEG, under a name of its own
            if let img = await self.image(p, image), let j = img.jpegData(compressionQuality: 0.95), let src = MontanaHandoff.lay(j) {
                return .file(["src": src, "name": src + ".jpg", "ext": "jpg"])
            }
            return nil
        }
        if p.hasItemConformingToTypeIdentifier(data) { return await shelve(p, data).map { .file($0) } }
        if p.hasItemConformingToTypeIdentifier(plain), let s = await text(p, plain) { return .words(s) }
        return nil
    }
    /// A file of the share laid on the handoff shelf as its source gave it -- the wall's own road, a post keeps its files as
    /// picked, never the chat's copy: copied inside the provider's callback, where its temporary file lives.
    static func shelve(_ p: NSItemProvider, _ t: String) async -> [String: String]? {
        await withCheckedContinuation { c in
            p.loadFileRepresentation(forTypeIdentifier: t) { u, _ in
                guard let u, let src = MontanaHandoff.lay(file: u) else { c.resume(returning: nil); return }
                let name = originalName(p, u)
                let ext = u.pathExtension.isEmpty ? (name as NSString).pathExtension : u.pathExtension
                c.resume(returning: ["src": src, "name": name, "ext": ext])
            }
        }
    }
}

/// THE SHEET'S HALF OF A POST ON ONE'S OWN WALL (the author's words 29.09 and 02.10 19:17): everything shared, read once -- the
/// words joined, every file laid on the handoff shelf as its source gave it, up to what a post takes (MTPostMeasure.files) --
/// and ONE record under "pendingWall", laid whole. The page that writes the post is the app's own (MTBoardComposer, opened by
/// MTBoard.takeFromSheet); the sheet walks no door and draws no page of its own.
enum ShareWallHandoff {
    /// THE WALL'S PAGE IS ONE TAP AWAY (the author's word 16.10.2026 16:0x UTC: «publishing to my own wall through Share works crooked
    /// and does not open the app to do everything there»). A share extension may not bring its app forward -- the App Extension
    /// Programming Guide gives NSExtensionContext.open to a widget and a message app alone, and the author's word of 10.10.2026 holds
    /// «in full accordance with Apple's rules» -- so the sheet leaves the person the platform's own door: one notice, at once, no sound,
    /// whose tap opens Montana on my wall's new-post page with what was shared (MTBoard.takeFromSheet, then MTBoardComposer.reopen).
    /// The page takes the notice off the list as it rises. Without the person's permission for notices the old road stands: the page
    /// waits for the app's next activation.
    static func bell() async {
        let c = UNMutableNotificationContent()
        c.title = String(localized: "My wall", bundle: MTLanguage.bundle)
        c.body = String(localized: "Tap to finish the post", bundle: MTLanguage.bundle)
        c.sound = nil
        c.threadIdentifier = MontanaHandoff.wallNotice
        c.userInfo = ["wall": 1]
        do {
            try await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: MontanaHandoff.wallNotice, content: c, trigger: nil))
            ShareSend.diag("sheet WALL notice laid -- one tap opens the page")
        } catch {
            ShareSend.diag("sheet WALL notice refused: \(error.localizedDescription)")
        }
    }
    static func hand(_ attachments: [NSItemProvider]) async -> Bool {
        var said: [String] = []
        var files: [[String: String]] = []
        var past = 0
        for p in attachments {
            switch await ShareRead.wallPart(p) {
            case .words(let s)?:
                said.append(s)
            case .file(let f)?:
                guard files.count < MTPostMeasure.files else {
                    past += 1
                    if let u = MontanaHandoff.url(f["src"] ?? "") { try? FileManager.default.removeItem(at: u) }
                    continue
                }
                files.append(f)
            case nil:
                ShareSend.diag("sheet WALL item unreadable types=\(p.registeredTypeIdentifiers.prefix(3).joined(separator: ","))")
            }
        }
        let text = said.filter { !$0.isEmpty }.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !files.isEmpty else { ShareSend.diag("sheet WALL nothing to hand"); return false }
        var rows: [[String: Any]] = []
        if let d = MontanaKeychain.get("pendingWall"),
           let a = (try? JSONSerialization.jsonObject(with: d)) as? [[String: Any]] { rows = a }
        rows.append(["id": UUID().uuidString, "words": text, "files": files])
        guard let d = try? JSONSerialization.data(withJSONObject: rows), MontanaKeychain.set("pendingWall", d) else {
            ShareSend.diag("sheet WALL REFUSED by the keychain files=\(files.count)")
            for f in files { if let u = MontanaHandoff.url(f["src"] ?? "") { try? FileManager.default.removeItem(at: u) } }
            return false
        }
        ShareSend.diag("sheet WALL laid files=\(files.count) past=\(past) chars=\(text.count) -- the app's page opens")
        return true
    }
}

// The width of a cell follows the width of the sheet: four to five columns.
extension SharePickerController: UICollectionViewDelegateFlowLayout {
    func collectionView(_ cv: UICollectionView, layout l: UICollectionViewLayout,
                        sizeForItemAt ip: IndexPath) -> CGSize {
        let cols = max(4, Int((cv.bounds.width - 24) / 84))
        let w = floor((cv.bounds.width - 24) / CGFloat(cols))
        return CGSize(width: w, height: w + 22)
    }
    func collectionView(_ cv: UICollectionView, layout l: UICollectionViewLayout,
                        insetForSectionAt s: Int) -> UIEdgeInsets {
        UIEdgeInsets(top: 4, left: 12, bottom: 12, right: 12)
    }
}

// A cell: a round face -- a picture, or black with a white initial -- the name, and a tick when chosen. One's own wall wears the
// platform's write glyph where a tick would stand: its circle opens the post's page and is never chosen.
// THE CIRCLE STANDS TRUE BY CONSTRUCTION (the author's word 17.10.2026 15:4x UTC: «on the share page the circle of the chosen one is
// found crooked -- make all of it system and native»): the ring was a layer placed by hand in the cell's layout from the face's
// centre, read before the content view had laid the face out -- on a first pass it stood where the face had been, not where it is.
// Now the circle is a view of its own (ShareRing), centred on the face by the layout engine and drawn from its own bounds in its own
// layout; the face keeps its size; the tick is one round badge on that same circle at 45 degrees.
// THE SEND FILLS THE CIRCLE (the same word: «the sending as the platform's nearby sharing -- around the circle it fills, system
// blue»): each chosen face waits, then its circle fills in the platform's blue from the top, clockwise, as the pieces land on the
// node, and closes, with «Sent» under the name, only when the node took that chat's letters.
final class ShareAvatarCell: UICollectionViewCell {
    enum Send: Equatable { case waiting, sending(Double), sent }
    private static let side: CGFloat = 60
    private static let ringSide: CGFloat = side + 10   // the face, a gap of two points and the ring's line around it
    private let avatar = UIImageView()
    private let initialLabel = UILabel()
    private let nameLabel = UILabel()
    private let stateLabel = UILabel()
    private let ring = ShareRing()
    private let check = ShareAvatarCell.badge("checkmark")
    private let pen = ShareAvatarCell.badge("square.and.pencil")

    /// A round badge drawn whole: the platform's blue disc, a white rim, the white glyph in its middle.
    private static func badge(_ glyph: String) -> UIView {
        let v = UIView()
        v.backgroundColor = .systemBlue
        v.layer.cornerRadius = 12
        v.layer.borderWidth = 2
        v.layer.borderColor = UIColor.white.cgColor
        v.isHidden = true
        v.translatesAutoresizingMaskIntoConstraints = false
        let i = UIImageView(image: UIImage(systemName: glyph, withConfiguration: UIImage.SymbolConfiguration(pointSize: 10, weight: .heavy)))
        i.tintColor = .white
        i.contentMode = .center
        i.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(i)
        NSLayoutConstraint.activate([
            v.widthAnchor.constraint(equalToConstant: 24), v.heightAnchor.constraint(equalToConstant: 24),
            i.centerXAnchor.constraint(equalTo: v.centerXAnchor), i.centerYAnchor.constraint(equalTo: v.centerYAnchor),
        ])
        return v
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        avatar.contentMode = .scaleAspectFill
        avatar.layer.masksToBounds = true
        avatar.layer.cornerRadius = Self.side / 2
        avatar.layer.borderWidth = 1   // the thin white rim every avatar wears (the chat list law)
        avatar.layer.borderColor = UIColor.white.withAlphaComponent(0.45).cgColor
        avatar.translatesAutoresizingMaskIntoConstraints = false
        initialLabel.textColor = .white   // the client's avatar law: a white letter on black
        initialLabel.font = .systemFont(ofSize: 22, weight: .semibold)
        initialLabel.textAlignment = .center
        initialLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.font = .systemFont(ofSize: 11)
        nameLabel.textAlignment = .center
        nameLabel.numberOfLines = 2
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        stateLabel.font = .systemFont(ofSize: 11)
        stateLabel.textAlignment = .center
        stateLabel.isHidden = true
        stateLabel.translatesAutoresizingMaskIntoConstraints = false
        ring.isHidden = true
        ring.translatesAutoresizingMaskIntoConstraints = false
        avatar.addSubview(initialLabel)
        contentView.addSubview(ring)
        contentView.addSubview(avatar)
        contentView.addSubview(nameLabel)
        contentView.addSubview(stateLabel)
        contentView.addSubview(check)
        contentView.addSubview(pen)
        // A badge's centre at 45 degrees: the tick on the ring's line, the pen on the face's rim -- the radius times the cosine of 45.
        let onRing = (Self.ringSide / 2 - ShareRing.line / 2) * 0.7071
        let onFace = (Self.side / 2) * 0.7071
        NSLayoutConstraint.activate([
            avatar.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 6),
            avatar.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            avatar.widthAnchor.constraint(equalToConstant: Self.side),
            avatar.heightAnchor.constraint(equalToConstant: Self.side),
            ring.centerXAnchor.constraint(equalTo: avatar.centerXAnchor),
            ring.centerYAnchor.constraint(equalTo: avatar.centerYAnchor),
            ring.widthAnchor.constraint(equalToConstant: Self.ringSide),
            ring.heightAnchor.constraint(equalToConstant: Self.ringSide),
            initialLabel.centerXAnchor.constraint(equalTo: avatar.centerXAnchor),
            initialLabel.centerYAnchor.constraint(equalTo: avatar.centerYAnchor),
            nameLabel.topAnchor.constraint(equalTo: avatar.bottomAnchor, constant: 6),
            nameLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 2),
            nameLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -2),
            stateLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 1),
            stateLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 2),
            stateLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -2),
            check.centerXAnchor.constraint(equalTo: avatar.centerXAnchor, constant: onRing),
            check.centerYAnchor.constraint(equalTo: avatar.centerYAnchor, constant: onRing),
            pen.centerXAnchor.constraint(equalTo: avatar.centerXAnchor, constant: onFace),
            pen.centerYAnchor.constraint(equalTo: avatar.centerYAnchor, constant: onFace),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    func configure(_ c: ShareChat, selected: Bool, send: Send?) {
        nameLabel.text = c.title
        if let t = c.thumb {
            avatar.image = t; avatar.backgroundColor = .clear; initialLabel.isHidden = true
        } else {
            // SSOT with the client's AvatarCircle fallback ([C-1]): a face without a photo is a black circle with its letter.
            avatar.image = nil
            avatar.backgroundColor = .black
            initialLabel.text = c.initial; initialLabel.isHidden = false
        }
        nameLabel.textColor = .label
        pen.isHidden = c.name != ShareChat.wallName
        show(selected: selected, send: send, animated: false)
    }

    /// The chosen one's ring and tick, or the send's circle and its word -- one circle, the same place.
    func show(selected: Bool, send: Send?, animated: Bool) {
        guard let send else {
            ring.tracked = false
            ring.set(1, animated: false)
            ring.isHidden = !selected
            check.isHidden = !selected
            stateLabel.isHidden = true
            nameLabel.numberOfLines = 2
            return
        }
        ring.isHidden = false
        ring.tracked = true
        check.isHidden = true
        nameLabel.numberOfLines = 1
        stateLabel.isHidden = false
        switch send {
        case .waiting:
            ring.set(0, animated: false)
            stateLabel.text = String(localized: "Waiting…", bundle: MTLanguage.bundle)
            stateLabel.textColor = .secondaryLabel
        case .sending(let f):
            ring.set(f, animated: animated)
            stateLabel.text = String(localized: "Sending…", bundle: MTLanguage.bundle)
            stateLabel.textColor = .secondaryLabel
        case .sent:
            ring.set(1, animated: animated)
            stateLabel.text = String(localized: "Sent", bundle: MTLanguage.bundle)
            stateLabel.textColor = .systemBlue
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        ring.isHidden = true; check.isHidden = true; pen.isHidden = true; stateLabel.isHidden = true
    }
}

/// One circle around a face, drawn from its own bounds in its own layout -- never from another view's frame: the chosen one's ring,
/// whole, and the send's, filling in the platform's blue from the top, clockwise, over a faint track.
final class ShareRing: UIView {
    static let line: CGFloat = 3
    private let track = CAShapeLayer()
    private let fill = CAShapeLayer()
    var tracked = false { didSet { track.isHidden = !tracked } }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        for l in [track, fill] {
            l.fillColor = UIColor.clear.cgColor
            l.lineWidth = Self.line
            l.lineCap = .round
            layer.addSublayer(l)
        }
        track.strokeColor = UIColor.white.withAlphaComponent(0.18).cgColor
        track.isHidden = true
        fill.strokeColor = UIColor.systemBlue.cgColor
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        let r = min(bounds.width, bounds.height) / 2 - Self.line / 2
        let round = UIBezierPath(arcCenter: CGPoint(x: bounds.midX, y: bounds.midY), radius: r,
                                 startAngle: -CGFloat.pi / 2, endAngle: CGFloat.pi * 1.5, clockwise: true).cgPath
        CATransaction.begin(); CATransaction.setDisableActions(true)
        for l in [track, fill] { l.frame = bounds; l.path = round }
        CATransaction.commit()
    }

    func set(_ fraction: Double, animated: Bool) {
        let to = CGFloat(max(0, min(1, fraction)))
        if animated {
            let a = CABasicAnimation(keyPath: "strokeEnd")
            a.fromValue = fill.presentation()?.strokeEnd ?? fill.strokeEnd
            a.toValue = to
            a.duration = 0.25
            a.timingFunction = CAMediaTimingFunction(name: .easeOut)
            fill.add(a, forKey: "fill")
        }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        fill.strokeEnd = to
        CATransaction.commit()
    }
}

extension UIColor {
    convenience init(montanaHex hex: String) {
        let h = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        var v: UInt64 = 0; Scanner(string: h).scanHexInt64(&v)
        self.init(red: CGFloat((v >> 16) & 0xff) / 255, green: CGFloat((v >> 8) & 0xff) / 255,
                  blue: CGFloat(v & 0xff) / 255, alpha: 1)
    }
}
