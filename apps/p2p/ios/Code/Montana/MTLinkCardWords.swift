import SwiftUI
import UIKit

/// THE WORDS OF A LINK CARD FLOW AROUND ITS SMALL PICTURE (the author's word 22.09: one to one with
/// the reference). The reference lays its card as three text nodes, each given a CUTOUT in its top
/// right corner -- the square the picture occupies -- and each node subtracts its own height from
/// what is left of that square, so the first lines are short and the lines below the picture run the
/// card's full width (ChatMessageAttachedContentNode: TextNodeCutout(topRight:), inlineMediaEdgeInset
/// = 6, the inline picture 54 by 54 at a four-point corner).
///
/// The platform carries that mechanism itself: NSTextContainer.exclusionPaths. So the card's words
/// are one view of ours over UIKit's own text engine -- three blocks, the reference's own line
/// counts (two for the site, five for the title, twelve for the words), its line spacing of nine
/// hundredths, and its cutout arithmetic, measured in one pass through sizeThatFits.
struct MTLinkCardWords: UIViewRepresentable {
    struct Block {
        let text: String
        let weight: UIFont.Weight
        let color: UIColor
        let lines: Int
    }
    let blocks: [Block]
    let size: CGFloat          // the card's font size: fourteen seventeenths of the letter's own
    let cutout: CGSize?        // the picture's square plus its six points, or nil when it stands alone

    private var spacing: CGFloat { size * 0.09 }

    func makeUIView(context: Context) -> MTLinkCardWordsView {
        let v = MTLinkCardWordsView()
        v.backgroundColor = .clear
        return v
    }

    func updateUIView(_ v: MTLinkCardWordsView, context: Context) {
        v.apply(blocks: blocks, size: size, spacing: spacing, cutout: cutout)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: MTLinkCardWordsView, context: Context) -> CGSize? {
        let w = max(proposal.width ?? uiView.bounds.width, 1)
        uiView.apply(blocks: blocks, size: size, spacing: spacing, cutout: cutout)
        return CGSize(width: w, height: uiView.height(for: w))
    }
}

/// The card's three blocks over UIKit's own text engine: one label per block, the picture's square
/// excluded from whatever part of it each block still meets.
final class MTLinkCardWordsView: UIView {
    private var views: [UITextView] = []
    private var blocks: [MTLinkCardWords.Block] = []
    private var size: CGFloat = 14
    private var spacing: CGFloat = 1
    private var cutout: CGSize?

    func apply(blocks: [MTLinkCardWords.Block], size: CGFloat, spacing: CGFloat, cutout: CGSize?) {
        self.blocks = blocks; self.size = size; self.spacing = spacing; self.cutout = cutout
        while views.count < blocks.count {
            let tv = UITextView()
            tv.isEditable = false
            tv.isScrollEnabled = false
            tv.isSelectable = false
            tv.backgroundColor = .clear
            tv.textContainerInset = .zero
            tv.textContainer.lineFragmentPadding = 0
            tv.textContainer.lineBreakMode = .byTruncatingTail
            addSubview(tv)
            views.append(tv)
        }
        for (i, tv) in views.enumerated() {
            tv.isHidden = !(i < blocks.count)
            guard i < blocks.count else { continue }
            let b = blocks[i]
            tv.attributedText = Self.string(b, size: size, spacing: spacing)
            tv.textContainer.maximumNumberOfLines = b.lines
        }
        setNeedsLayout()
    }

    private static func string(_ b: MTLinkCardWords.Block, size: CGFloat, spacing: CGFloat) -> NSAttributedString {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = spacing
        style.lineBreakMode = .byTruncatingTail
        return NSAttributedString(string: b.text, attributes: [
            .font: UIFont.systemFont(ofSize: size, weight: b.weight),
            .foregroundColor: b.color,
            .paragraphStyle: style,
        ])
    }

    /// THE REFERENCE'S OWN ARITHMETIC: the picture's square is taken out of the first block, what
    /// remains of it out of the next, and so on -- so the words close under the picture, never beside
    /// a column of empty air.
    private func frames(for width: CGFloat) -> [CGRect] {
        var out: [CGRect] = []
        var y: CGFloat = 0
        var left = cutout?.height ?? 0
        for (i, _) in blocks.enumerated() where i < views.count {
            let tv = views[i]
            let hole: CGRect? = left > 0 ? CGRect(x: width - (cutout?.width ?? 0), y: 0,
                                                  width: cutout?.width ?? 0, height: left) : nil
            tv.textContainer.exclusionPaths = hole.map { [UIBezierPath(rect: $0)] } ?? []
            tv.textContainer.size = CGSize(width: width, height: 100000)
            tv.layoutManager.ensureLayout(for: tv.textContainer)
            let h = ceil(tv.layoutManager.usedRect(for: tv.textContainer).height)
            out.append(CGRect(x: 0, y: y, width: width, height: h))
            y += h
            left = max(0, left - h)
        }
        return out
    }

    func height(for width: CGFloat) -> CGFloat {
        frames(for: width).last.map { $0.maxY } ?? 0
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let f = frames(for: bounds.width)
        for (i, r) in f.enumerated() where i < views.count { views[i].frame = r }
    }
}
