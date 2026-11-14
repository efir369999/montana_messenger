import SwiftUI
import UIKit

// The words of a letter while the menu stands.
//
// The system's own text view draws them, so a person can take a PART of them: two knobs, the
// magnifier, drag to widen, and the system's menu over exactly what is chosen. SwiftUI's own
// selection was tried first and named: it takes the whole block and offers one Copy, with nothing
// to drag — that is copying a letter, not selecting text.
//
// The wait before the words are caught is 0.3 s — the same 0.3 s a text view waits
// before it catches a word — so the selection arrives at the speed of the menu that opened it, and
// the first thing caught is the WORD under the finger, not a bare caret. The recognizer that
// measures the wait is our own: nothing is reset on the system's recognizers after their birth.
final class MTMessageTextView: UITextView {
    // The menu over the chosen words is ours, born here. The system's text view keeps its own
    // for its own long press; asking that one to open would be reaching into a foreign object
    // after its birth, and it is not offered to us anyway.
    let selectionMenu = UIEditMenuInteraction(delegate: nil)

    // The container is pinned to the view's width on every layout, so a line wraps at the bubble's
    // edge and an unbroken word wraps by itself instead of walking off sideways.
    override func layoutSubviews() {
        super.layoutSubviews()
        let w = bounds.width
        if w > 1, textContainer.size.width != w {
            textContainer.size = CGSize(width: w, height: 1_000_000)
        }
    }
}

struct MTMessageText: UIViewRepresentable {
    let text: String
    let font: UIFont
    let color: UIColor

    func makeUIView(context: Context) -> MTMessageTextView {
        let v = MTMessageTextView()
        v.isEditable = false
        v.isSelectable = true
        v.isScrollEnabled = false
        v.backgroundColor = .clear
        v.textContainerInset = .zero
        v.textContainer.lineFragmentPadding = 0
        v.dataDetectorTypes = []
        // The knobs and the highlight take the view's tint. Grey-white and translucent, the same
        // material the menu above them is made of, so the two read as one thing on any bubble.
        v.tintColor = UIColor(white: 0.92, alpha: 0.55)
        v.textDragInteraction?.isEnabled = false
        v.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        v.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let hold = UILongPressGestureRecognizer(target: context.coordinator,
                                                action: #selector(Coordinator.hold(_:)))
        hold.minimumPressDuration = 0.3
        hold.delegate = context.coordinator
        v.addGestureRecognizer(hold)
        // ONE owner of the question "when does the menu open": a finger that was on the words has
        // lifted and something is chosen. It answers for the first catch and for every knob drag
        // alike, because a recognizer on the view also sees the touches its subviews receive —
        // and the knobs are its subviews. Two separate answers to one question would drift apart.
        let lift = UILongPressGestureRecognizer(target: context.coordinator,
                                                action: #selector(Coordinator.lift(_:)))
        lift.minimumPressDuration = 0
        lift.cancelsTouchesInView = false
        lift.delaysTouchesEnded = false
        lift.delegate = context.coordinator
        v.addGestureRecognizer(lift)
        v.addInteraction(v.selectionMenu)
        return v
    }

    func updateUIView(_ v: MTMessageTextView, context: Context) {
        if v.font != font { v.font = font }
        if v.textColor != color { v.textColor = color }
        if v.text != text { v.text = text }
    }

    // THE HEIGHT IS A FUNCTION OF (TEXT, FONT, WIDTH) AND OF NOTHING ELSE.
    //
    // It used to be measured ON the live view: the measurement set the view's own text container
    // to the proposed width and read the result back. But the view's container has a second owner
    // — its layout, which pins the container to the view's real width on every pass — and the
    // system reuses that view for the next letter. So the answer depended on WHICH OWNER RAN LAST
    // and on what the view still carried from the previous letter: the first opening measured
    // right, the second measured against leftovers and the bubble clipped. Two owners of one
    // value is the whole defect ([C-1]).
    //
    // Now measuring touches no view at all. A throwaway layout stack is built from the inputs,
    // gives the height, and dies. The same three inputs always give the same answer, in any order,
    // at any opening, for any reuse — there is nothing left to be stale.
    // THE ANSWER IS THE BOX THE LINES ACTUALLY OCCUPY — both of its sides.
    //
    // Answering with the PROPOSED width was the whole defect. The width a letter is offered is not
    // the width it gets: ahead of it stand the spacer beside one's own bubble and the padding of
    // the cloud, and when no width is proposed at all the widest a bubble may be is only an upper
    // bound. Measured in a wider box than the one it lands in, the text counts fewer lines than it
    // will have — the height comes out short, one more sentence wraps on screen, and the view
    // clips it. The same answer also made every bubble in the menu as wide as the limit, instead
    // of as wide as its own words.
    //
    // So the measurement returns the rectangle its own layout produced, never wider than offered.
    // The width handed back already holds every line, so nothing can re-wrap inside it, and there
    // is nothing left to cut.
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: MTMessageTextView, context: Context) -> CGSize? {
        MTMessageText.fitted(proposal, text: text, font: font)
    }

    /// The one answer of every letter's words to a proposed size (the menu's, a link's, a long letter's): the box, never wider than offered.
    static func fitted(_ proposal: ProposedViewSize, text: String, font: UIFont) -> CGSize {
        let limit = max(proposal.width ?? widestBubble, 1)
        let box = MTMessageText.box(of: text, font: font, maxWidth: limit)
        return CGSize(width: min(box.width, limit), height: max(box.height, ceil(font.lineHeight)))
    }

    static func box(of text: String, font: UIFont, maxWidth: CGFloat) -> CGSize {
        box(of: text, font: font, maxWidth: maxWidth, lines: 0)
    }
    /// The same box for a folded post's first lines (MTPostFold): the platform's own cut of the container.
    /// THE BOX IS KEPT BY ITS INPUTS (28.09): SwiftUI asks a letter's size several times in one layout and again at every
    /// reconfiguration of its cell, and every answer built a whole layout stack over the words (a long letter's cell stood 160-290
    /// ms on T1's scroll of the long chat). The box is a function of these inputs and of nothing else (above), so the answer is
    /// kept under them, in the platform's own cache, safe from any thread.
    private final class KeptBox { let size: CGSize; init(_ size: CGSize) { self.size = size } }
    private static let keptBoxes: NSCache<NSString, KeptBox> = { let c = NSCache<NSString, KeptBox>(); c.countLimit = 1024; return c }()
    static func box(of text: String, font: UIFont, maxWidth: CGFloat, lines: Int) -> CGSize {
        let key = "\(font.fontName)/\(font.pointSize)/\(maxWidth)/\(lines)/\(text)" as NSString
        if let kept = keptBoxes.object(forKey: key) { return kept.size }
        let began = CACurrentMediaTime()
        let size = laidBox(of: text, font: font, maxWidth: maxWidth, lines: lines)
        keptBoxes.setObject(KeptBox(size), forKey: key)
        // A long letter's first measure is the one layout still made where it is asked: its cost is said by name, once per box.
        if MTTiledLetter.isLong(text) {
            MontanaTrace.mark("letter_box", "bytes=\(text.utf8.count) ms=\(Int((CACurrentMediaTime() - began) * 1000)) main=\(Thread.isMainThread)")
        }
        return size
    }
    private static func laidBox(of text: String, font: UIFont, maxWidth: CGFloat, lines: Int) -> CGSize {
        let storage = NSTextStorage(string: text, attributes: [.font: font])
        let container = NSTextContainer(size: CGSize(width: maxWidth, height: 1_000_000))
        container.lineFragmentPadding = 0
        container.maximumNumberOfLines = lines
        if lines != 0 { container.lineBreakMode = .byTruncatingTail }
        let layout = NSLayoutManager()
        layout.addTextContainer(container)
        storage.addLayoutManager(layout)
        layout.ensureLayout(for: container)
        let used = layout.usedRect(for: container)
        return CGSize(width: max(1, ceil(used.width)), height: ceil(used.height))
    }

    // The widest a bubble is allowed to be: four fifths of the window, less the bubble's own side
    // padding. The same fraction the feed lays bubbles out by ([C-1]).
    static var widestBubble: CGFloat { widest(MTScene.size().width) }
    /// The same fraction for a window the caller already holds (the chat's own, mtWindowSize); no window yet, the scene's.
    static func widest(_ window: CGFloat) -> CGFloat {
        let win = window > 0 ? window : MTScene.size().width
        return max(80, (win > 0 ? win : 320) * 0.80 - 24)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        // The word under the finger, caught after the same 0.3 s wait.
        @objc func hold(_ g: UILongPressGestureRecognizer) {
            // SILENT-OK: a gesture reports every phase and a finger may land where there is no
            // text; not catching a word is the ordinary course of a touch, not a failed delivery.
            guard g.state == .began, let v = g.view as? MTMessageTextView else { return }
            let p = g.location(in: v)
            guard v.becomeFirstResponder(), let pos = v.closestPosition(to: p) else { return }
            let word = v.tokenizer.rangeEnclosingPosition(pos, with: .word, inDirection: .storage(.backward))
                ?? v.tokenizer.rangeEnclosingPosition(pos, with: .word, inDirection: .storage(.forward))
            v.selectedTextRange = word ?? v.textRange(from: pos, to: pos)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }

        // The finger lifts: if words are chosen, the menu stands over them. A menu opened while
        // the touch is still down is dismissed by that same touch — it appears and goes in one
        // instant, which from the outside is indistinguishable from no menu at all.
        @objc func lift(_ g: UILongPressGestureRecognizer) {
            // SILENT-OK: every phase of a touch arrives here; only its end asks a question, and
            // a touch that chose nothing has nothing to ask about.
            guard g.state == .ended || g.state == .cancelled,
                  let v = g.view as? MTMessageTextView,
                  v.selectedTextRange?.isEmpty == false else { return }
            let p = g.location(in: v)
            DispatchQueue.main.async {
                v.selectionMenu.presentEditMenu(
                    with: UIEditMenuConfiguration(identifier: nil, sourcePoint: p))
            }
        }

        func gestureRecognizer(_ g: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
    }
}

/// THE LINK IS THE PLATFORM'S OWN (the author's word 22.09: a link must be a link, with no «http://»
/// in front of it and among other words too). Two defects stood behind the dead link: the finder was
/// let past a gate that demanded «://» or «www.» in the letter, so a bare «montana.quest» was never
/// looked at; and a SwiftUI text drawn inside a node that carries the letter's own tap hands that tap
/// to the node, so even a found link did not open.
///
/// Both are closed by giving the words to the platform: a UITextView draws them with the system's own
/// link detection (NSDataDetector by way of `dataDetectorTypes`, which knows a bare host), and the view
/// answers a touch ONLY where a link lies — `point(inside:)` says «not mine» everywhere else, so the
/// bubble's tap, the feed's hold, the reply swipe and the scroll all keep every touch they had.
final class MTLinkTextView: UITextView {
    /// A post's own page gives its words every touch, the selection's too (02.10); everywhere else a link alone answers.
    var takesEveryTouch = false
    override func layoutSubviews() {
        super.layoutSubviews()
        let w = bounds.width
        if w > 1, textContainer.size.width != w {
            textContainer.size = CGSize(width: w, height: 1_000_000)
        }
    }
    /// The point is the view's only if a link lies under it -- or anywhere, where the words take every touch.
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        takesEveryTouch ? super.point(inside: point, with: event) : link(at: point)
    }
    /// Whether a link lies under the point (a post's tap asks it too, so a post never opens over its link).
    func link(at point: CGPoint) -> Bool {
        guard bounds.contains(point), !text.isEmpty else { return false }
        let inset = CGPoint(x: point.x - textContainerInset.left, y: point.y - textContainerInset.top)
        let i = layoutManager.characterIndex(for: inset, in: textContainer,
                                             fractionOfDistanceBetweenInsertionPoints: nil)
        guard i >= 0, i < textStorage.length else { return false }
        let glyph = layoutManager.glyphIndexForCharacter(at: i)
        let box = layoutManager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: textContainer)
        guard box.insetBy(dx: -2, dy: -2).contains(inset) else { return false }   // past the last glyph of a line is not a link
        return textStorage.attribute(.link, at: i, effectiveRange: nil) != nil
    }
}

/// The words of a letter that carries a link: the same size, the same font, the same colour as the
/// drawn text beside it — the link underlined in the bubble's own link colour.
struct MTLinkedText: UIViewRepresentable {
    let text: String
    let font: UIFont
    let color: UIColor
    let linkColor: UIColor

    func makeUIView(context: Context) -> MTLinkTextView {
        let v = MTLinkTextView()
        v.isEditable = false
        v.isSelectable = true          // the platform opens a link only on a view that may be touched
        v.isScrollEnabled = false
        v.backgroundColor = .clear
        v.textContainerInset = .zero
        v.textContainer.lineFragmentPadding = 0
        // THE LINKS ARE THE ONE FINDER'S (MTLinks, 02.10): it knows a bare host, with no scheme before it, and a Montana
        // link, which the system's own detector never marked -- the shared post arrived as dead words.
        v.dataDetectorTypes = []
        v.textDragInteraction?.isEnabled = false
        v.delegate = MTTextLinks.shared   // a post's link in a letter: its preview on a hold, its page at a tap (06.10)
        v.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        v.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return v
    }

    func updateUIView(_ v: MTLinkTextView, context: Context) {
        let words = MTLinks.marked(text, attributes: [.font: font, .foregroundColor: color])
        if !v.attributedText.isEqual(to: words) { v.attributedText = words }
        let link: [NSAttributedString.Key: Any] = [.foregroundColor: linkColor,
                                                   .underlineStyle: NSUnderlineStyle.single.rawValue]
        if !NSDictionary(dictionary: v.linkTextAttributes).isEqual(to: link) { v.linkTextAttributes = link }
    }

    /// The same measure the menu's words use ([C-1]): the box the lines actually occupy.
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: MTLinkTextView, context: Context) -> CGSize? {
        MTMessageText.fitted(proposal, text: text, font: font)
    }
}

/// A LONG LETTER IS DRAWN AWAY FROM THE MAIN THREAD (the author's words of 14.11.2026 01:35 UTC, «there are very long letters in
/// this chat», and of the same night, «there must be no stalls at all»; decision 931: the look stays, a chat's letter never folds).
/// Measured on T1, build 2394: SwiftUI drew such a letter as one text inside the main thread's commit at every appearance of
/// its chat and at every leaving -- up to 275 ms in one frame, 19-22 of about 30 samples of each opening. Here the platform's
/// tiled layer draws the same words through the TextKit stack that measures them (MTMessageText.box): tile by tile, on its own
/// threads, only what the screen shows; the lines are laid out there too, once, and kept. The main thread draws nothing.
enum MTTiledLetter {
    /// From here a letter is long: a kilobyte of words is a dozen lines and more; under it SwiftUI's own text costs less than a frame.
    static let bytes = 1024
    static func isLong(_ s: String) -> Bool { bytes <= s.utf8.count }
}

/// The laid lines of one long letter at one width: a TextKit stack of its own, touched by one thread at a time.
final class MTTiledLetterPage {
    private let gate = NSLock()
    private let storage: NSTextStorage
    private let layout = NSLayoutManager()
    private let container: NSTextContainer
    private init(text: String, font: UIFont, ink: UIColor, width: CGFloat) {
        storage = NSTextStorage(string: text, attributes: [.font: font, .foregroundColor: ink])
        container = NSTextContainer(size: CGSize(width: width, height: 1_000_000))
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)
        storage.addLayoutManager(layout)
    }
    /// The lines under a tile: laid out for the first tile that asks, kept for every later one.
    func draw(_ tile: CGRect) {
        gate.lock(); defer { gate.unlock() }
        let glyphs = layout.glyphRange(forBoundingRect: tile, in: container)
        layout.drawGlyphs(forGlyphRange: glyphs, at: .zero)
    }
    /// A PAGE IS KEPT BY ITS INPUTS, as the box is: a chat opened again draws its tiles from lines already laid.
    private static let pages: NSCache<NSString, MTTiledLetterPage> = {
        let c = NSCache<NSString, MTTiledLetterPage>(); c.countLimit = 8; return c
    }()
    static func kept(text: String, font: UIFont, ink: UIColor, width: CGFloat) -> MTTiledLetterPage {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        _ = ink.getRed(&r, green: &g, blue: &b, alpha: &a)
        let key = "\(font.fontName)/\(font.pointSize)/\(width)/\(r),\(g),\(b),\(a)/\(text)" as NSString
        if let page = pages.object(forKey: key) { return page }
        let page = MTTiledLetterPage(text: text, font: font, ink: ink, width: width)
        pages.setObject(page, forKey: key)
        return page
    }
}

/// The platform's tiled layer: it asks for each tile on a thread of its own and keeps what it drew.
final class MTTiledLetterTiles: CATiledLayer {
    override class func fadeDuration() -> CFTimeInterval { 0 }   // the words stand at once, as drawn text does
    private let gate = NSLock()
    private var held: MTTiledLetterPage?
    var page: MTTiledLetterPage? {
        get { gate.lock(); defer { gate.unlock() }; return held }
        set { gate.lock(); held = newValue; gate.unlock() }
    }
    override func draw(in ctx: CGContext) {
        guard let page else { return }
        UIGraphicsPushContext(ctx)
        page.draw(ctx.boundingBoxOfClipPath)
        UIGraphicsPopContext()
    }
}

/// The view of a long letter's words: it holds what to draw and hands the tiles their page; it draws nothing itself.
final class MTTiledLetterView: UIView {
    override class var layerClass: AnyClass { MTTiledLetterTiles.self }
    private var words: (text: String, font: UIFont, color: UIColor)?
    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        isAccessibilityElement = true
        accessibilityTraits = .staticText
        layer.needsDisplayOnBoundsChange = true
        (layer as? CATiledLayer)?.tileSize = CGSize(width: 1024, height: 1024)
        // The ink follows the light and the dark: a new colour is a new page.
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (v: MTTiledLetterView, _: UITraitCollection) in v.setNeedsLayout() }
    }
    required init?(coder: NSCoder) { nil }
    func show(_ text: String, _ font: UIFont, _ color: UIColor) {
        if let w = words, w.font == font, w.color == color, w.text == text { return }
        words = (text, font, color)
        accessibilityLabel = text
        setNeedsLayout()
    }
    /// The touch is never the words': the bubble's tap, the feed's hold, the reply swipe and the scroll keep all they had.
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool { false }
    override func layoutSubviews() {
        super.layoutSubviews()
        guard let words, 1 < bounds.width, let tiles = layer as? MTTiledLetterTiles else { return }
        tiles.contentsScale = max(traitCollection.displayScale, 1)
        let page = MTTiledLetterPage.kept(text: words.text, font: words.font,
                                         ink: words.color.resolvedColor(with: traitCollection), width: bounds.width)
        if tiles.page !== page {
            tiles.page = page
            tiles.setNeedsDisplay()
        }
    }
}

/// The words of a long letter in the feed: the same words, font and colour as the drawn text of a short one.
struct MTTiledLetterText: UIViewRepresentable {
    let text: String
    let font: UIFont
    let color: UIColor
    func makeUIView(context: Context) -> MTTiledLetterView {
        let v = MTTiledLetterView()
        v.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        v.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return v
    }
    func updateUIView(_ v: MTTiledLetterView, context: Context) { v.show(text, font, color) }
    /// The same measure every letter's words use ([C-1]): the box the lines actually occupy.
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: MTTiledLetterView, context: Context) -> CGSize? {
        MTMessageText.fitted(proposal, text: text, font: font)
    }
}

/// Only posts fold (the author's word 27.09). Chat bubbles show their whole text as in 1960.
/// The post's font and actual proposed width decide the fold through the same TextKit stack that draws its words.
enum MTPostFold {
    /// The post preview keeps its existing eight-line limit.
    static let foldLines = 8
    private static let memo = NSCache<NSString, NSNumber>()

    static func folds(_ text: String, font: UIFont, width: CGFloat) -> Bool {
        let key = "\(font.pointSize)/\(Int(width))/\(text.hashValue)" as NSString
        if let known = memo.object(forKey: key) { return known.boolValue }
        let folded = lines(of: text, font: font, width: width, upTo: foldLines) > foldLines
        memo.setObject(NSNumber(value: folded), forKey: key)
        return folded
    }

    /// The lines the words take at this width, counted no further than one past the cap: the container holds the cap and two
    /// lines more, so a letter of four thousand characters is laid out for its first ten lines, not for all of them.
    static func lines(of text: String, font: UIFont, width: CGFloat, upTo cap: Int) -> Int {
        let storage = NSTextStorage(string: text, attributes: [.font: font])
        let container = NSTextContainer(size: CGSize(width: max(width, 1), height: ceil(font.lineHeight) * CGFloat(cap + 2)))
        container.lineFragmentPadding = 0
        let layout = NSLayoutManager()
        layout.addTextContainer(container)
        storage.addLayoutManager(layout)
        let laid = layout.glyphRange(for: container)
        var count = 0
        layout.enumerateLineFragments(forGlyphRange: laid) { _, _, _, _, _ in count += 1 }
        return laid.location + laid.length == layout.numberOfGlyphs ? count : cap + 1
    }
}

/// A letter opened whole: its name in the feed and its words.
struct MTLetterRead: Hashable, Identifiable {
    let id: MID
    let text: String
    /// The page's title: the letter's first line, as the system's page heads a long letter.
    var title: String {
        let words = MTRowLetter.words(text)
        let first = words.split(whereSeparator: \.isNewline).first.map(String.init) ?? words
        return first.trimmingCharacters(in: .whitespaces)
    }
}

/// THE WHOLE LETTER ON A PAGE OF ITS OWN (the author's word 26.09: «as the same letter goes natively in the system's messages»):
/// the chat pushes it on its own stack -- the system's back, the letter's first line for a title -- and the platform's own text
/// view holds the words: it scrolls, a part of them is taken by the system's selection, a link opens where it lies, and a long
/// word breaks across lines as the system's page breaks it.
struct MTLetterPage: View {
    let letter: MTLetterRead
    var body: some View {
        MTLetterPageText(text: MTRowLetter.words(letter.text), font: MontanaTextSize.letterFont(.body))
            .ignoresSafeArea(.container, edges: .bottom)
            .background(Color(uiColor: .systemBackground).ignoresSafeArea())
            // USER-DATA: the letter's own first line
            .navigationTitle(Text(verbatim: letter.title))
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { MontanaTrace.mark("letter_page", "open chars=\(letter.text.count)") }
    }
}

/// The platform's text view over the whole letter: scrolling, selectable, links found by the system, words hyphenated.
struct MTLetterPageText: UIViewRepresentable {
    let text: String
    let font: UIFont
    func makeUIView(context: Context) -> UITextView {
        let v = UITextView()
        v.isEditable = false
        v.isSelectable = true
        v.isScrollEnabled = true
        v.alwaysBounceVertical = true
        v.backgroundColor = .clear
        v.textContainerInset = UIEdgeInsets(top: 8, left: 16, bottom: 24, right: 16)
        v.textContainer.lineFragmentPadding = 0
        v.dataDetectorTypes = []   // the one finder's links (MTLinks), a Montana link among them (02.10)
        v.linkTextAttributes = [.foregroundColor: UIColor.link]
        v.attributedText = Self.words(text, font)
        return v
    }
    func updateUIView(_ v: UITextView, context: Context) {
        if v.attributedText.string != text { v.attributedText = Self.words(text, font) }
    }
    static func words(_ s: String, _ font: UIFont) -> NSAttributedString {
        let p = NSMutableParagraphStyle()
        p.hyphenationFactor = 1   // the system's page breaks a long word across lines (the author's screenshot, 26.09)
        return MTLinks.marked(s, attributes: [.font: font, .foregroundColor: UIColor.label, .paragraphStyle: p])
    }
}

/// A LINK IN A TEXT ANSWERS AS THE PLATFORM'S LINKS DO (06.10; slice S4c2: the one delegate of every text view that carries links,
/// every edition's): a YouTube link plays here, in YouTube's own player, in the Protocol alone (MTApps.youtube, the author's word
/// 17.10.2026 13:4x UTC; Messenger compiles none, cut C4); in the Protocol a post's link answers by its door (cut C6); a Montana
/// link goes to the one entrance of a link (MontanaMeeting.isMontana); every other link keeps the platform's own tap and hold.
final class MTTextLinks: NSObject, UITextViewDelegate {
    static let shared = MTTextLinks()
    func textView(_ textView: UITextView, primaryActionFor textItem: UITextItem, defaultAction: UIAction) -> UIAction? {
        guard case .link(let url) = textItem.content else { return defaultAction }
        #if !MONTANA_MESSENGER
        if MTLinkPreviewBuilder.youtube(url) != nil, let tube = MTApps.youtube { return UIAction { _ in _ = tube.play(url, title: nil) } }
        #endif
        #if !MONTANA_MESSENGER
        if let wall = MTApps.wall?.linkAction(url) { return wall }
        #endif
        if MontanaMeeting.isMontana(url) { return UIAction { _ in MontanaMeeting.handleLink(url) } }
        return defaultAction
    }
    #if !MONTANA_MESSENGER
    func textView(_ textView: UITextView, menuConfigurationFor textItem: UITextItem,
                  defaultMenu: UIMenu) -> UITextItem.MenuConfiguration? {
        guard case .link(let url) = textItem.content, let m = MTApps.wall?.linkMenu(url, in: textView) else {
            return .init(preview: .default, menu: defaultMenu)
        }
        return m
    }
    #endif
}
