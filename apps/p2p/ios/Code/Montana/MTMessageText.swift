import SwiftUI
import UIKit

// The words of a letter while the menu stands.
//
// The system's own text view draws them, so a person can take a PART of them: two knobs, the
// magnifier, drag to widen, and the system's menu over exactly what is chosen. SwiftUI's own
// selection was tried first and named: it takes the whole block and offers one Copy, with nothing
// to drag — that is copying a letter, not selecting text.
//
// The wait before the words are caught is 0.3 s — the reference client measures the same 0.3 s
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
        let limit = max(proposal.width ?? MTMessageText.widestBubble, 1)
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
        let size = laidBox(of: text, font: font, maxWidth: maxWidth, lines: lines)
        keptBoxes.setObject(KeptBox(size), forKey: key)
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
        // The word under the finger, caught after the same wait the reference client waits.
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
        v.delegate = MTPostLinkPeek.shared   // a post's link in a letter: its preview on a hold, its page at a tap (06.10)
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
        let limit = max(proposal.width ?? MTMessageText.widestBubble, 1)
        let box = MTMessageText.box(of: text, font: font, maxWidth: limit)
        return CGSize(width: min(box.width, limit), height: max(box.height, ceil(font.lineHeight)))
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
            .onAppear { MontanaP2PTrace.mark("letter_page", "open chars=\(letter.text.count)") }
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
