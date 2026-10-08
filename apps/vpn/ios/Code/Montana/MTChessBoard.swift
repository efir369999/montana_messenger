import SwiftUI
import UIKit

enum MTChessPalette {
    // Sampled from the supplied board, in sRGB. The artwork is kept byte-for-byte.
    static let light = UIColor(red: 238/255, green: 238/255, blue: 214/255, alpha: 1)
    static let dark = UIColor(red: 124/255, green: 149/255, blue: 92/255, alpha: 1)
    static let lastLight = UIColor(red: 246/255, green: 246/255, blue: 146/255, alpha: 1)
    static let lastDark = UIColor(red: 186/255, green: 202/255, blue: 68/255, alpha: 1)
    static func asset(_ piece: MTChessPiece) -> String { "Chess" + (piece.side == .white ? "w" : "b") + piece.kind.rawValue }
}

struct MTChessIcon: View {
    var body: some View {
        Image("Chesswn").resizable().scaledToFit().accessibilityHidden(true)
    }
}

struct MTChessBoard: UIViewRepresentable {
    static let minimumSide = montanaTouchTarget * 8
    let position: MTChessPosition
    let facing: MTChessSide
    let selected: Int?
    let destinations: Set<Int>
    let lastMove: MTChessMove?
    let enabled: Bool
    let onSquare: (Int) -> Void
    func makeUIView(context: Context) -> MTChessBoardScroll { MTChessBoardScroll() }
    func updateUIView(_ view: MTChessBoardScroll, context: Context) {
        view.board.configure(position: position, facing: facing, selected: selected,
                             destinations: destinations, lastMove: lastMove, enabled: enabled, onSquare: onSquare)
    }
}

final class MTChessBoardScroll: UIScrollView, UIScrollViewDelegate {
    let board = MTChessBoardCanvas()
    override init(frame: CGRect) {
        super.init(frame: frame)
        delegate = self; addSubview(board)
        minimumZoomScale = 1; maximumZoomScale = 3
        showsHorizontalScrollIndicator = false; showsVerticalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never
        backgroundColor = MTChessPalette.dark
    }
    required init?(coder: NSCoder) { nil }
    override func layoutSubviews() {
        super.layoutSubviews()
        // On a narrow window, the platform pans the board; hit regions never overlap adjacent squares.
        let side = max(MTChessBoard.minimumSide, min(bounds.width, bounds.height))
        if abs(board.bounds.width - side) > 0.5 && zoomScale == 1 {
            board.frame = CGRect(x: 0, y: 0, width: side, height: side)
            contentSize = board.bounds.size
            board.setNeedsDisplay(); board.setNeedsLayout()
        }
    }
    func viewForZooming(in scrollView: UIScrollView) -> UIView? { board }
}

private final class MTChessSquareElement: UIAccessibilityElement {
    var press: (() -> Void)?
    override func accessibilityActivate() -> Bool { press?(); return press != nil }
}

final class MTChessBoardCanvas: UIView {
    private var position = MTChessPosition()
    private var facing: MTChessSide = .white
    private var selected: Int?
    private var destinations: Set<Int> = []
    private var lastMove: MTChessMove?
    private var enabled = false
    private var onSquare: ((Int) -> Void)?
    private static let artwork: [String: UIImage] = {
        var result: [String: UIImage] = [:]
        for side: MTChessSide in [.white, .black] {
            for kind in MTChessKind.allCases {
                let name = MTChessPalette.asset(.init(side: side, kind: kind))
                result[name] = UIImage(named: name)
            }
        }
        return result
    }()
    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = true; isAccessibilityElement = false
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tap(_:))))
    }
    required init?(coder: NSCoder) { nil }
    func configure(position: MTChessPosition, facing: MTChessSide, selected: Int?, destinations: Set<Int>,
                   lastMove: MTChessMove?, enabled: Bool, onSquare: @escaping (Int) -> Void) {
        let changed = self.position != position || self.facing != facing || self.selected != selected
            || self.destinations != destinations || self.lastMove != lastMove || self.enabled != enabled
        self.position = position; self.facing = facing; self.selected = selected
        self.destinations = destinations; self.lastMove = lastMove; self.enabled = enabled; self.onSquare = onSquare
        if changed { setNeedsDisplay(); rebuildAccessibility() }
    }
    private func square(_ row: Int, _ col: Int) -> Int { facing == .white ? (7 - row) * 8 + col : row * 8 + 7 - col }
    @objc private func tap(_ gesture: UITapGestureRecognizer) {
        let p = gesture.location(in: self)
        guard enabled, bounds.contains(p), bounds.width > 0 else { return }
        onSquare?(square(min(7, Int(p.y / (bounds.height / 8))), min(7, Int(p.x / (bounds.width / 8)))))
    }
    override func layoutSubviews() { super.layoutSubviews(); rebuildAccessibility() }
    private func rebuildAccessibility() {
        guard bounds.width > 0 else { return }
        let side = bounds.width / 8
        accessibilityElements = (0..<64).map { n -> MTChessSquareElement in
            let row = n / 8, col = n % 8, sq = square(row, col)
            let element = MTChessSquareElement(accessibilityContainer: self)
            let piece = position.piece(at: sq)
            element.accessibilityLabel = MTChessPosition.square(sq) + (piece.map { ", " + MTChessWords.piece($0) } ?? "")
            element.accessibilityTraits = enabled ? [.button] : [.staticText]
            if sq == selected { element.accessibilityTraits.insert(.selected) }
            element.accessibilityFrameInContainerSpace = CGRect(x: CGFloat(col) * side, y: CGFloat(row) * side, width: side, height: side)
            element.press = enabled ? { [weak self] in self?.onSquare?(sq) } : nil
            return element
        }
    }
    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        let cell = bounds.width / 8
        for row in 0..<8 { for col in 0..<8 {
            let sq = square(row, col), light = (sq / 8 + sq % 8) % 2 == 1
            let box = CGRect(x: CGFloat(col) * cell, y: CGFloat(row) * cell, width: cell, height: cell)
            let highlighted = lastMove?.from == sq || lastMove?.to == sq || selected == sq
            let color = highlighted ? (light ? MTChessPalette.lastLight : MTChessPalette.lastDark)
                : (light ? MTChessPalette.light : MTChessPalette.dark)
            context.setFillColor(color.cgColor); context.fill(box)
            if let p = position.piece(at: sq) {
                if p.kind == .king && position.checked(p.side) {
                    context.setFillColor(UIColor.systemRed.withAlphaComponent(0.55).cgColor); context.fill(box)
                }
                Self.artwork[MTChessPalette.asset(p)]?.draw(in: box)
            }
            if destinations.contains(sq) {
                context.setFillColor(UIColor.black.withAlphaComponent(0.2).cgColor)
                if position.piece(at: sq) == nil { context.fillEllipse(in: box.insetBy(dx: cell * 0.36, dy: cell * 0.36)) }
                else {
                    context.setStrokeColor(UIColor.black.withAlphaComponent(0.25).cgColor); context.setLineWidth(cell * 0.07)
                    context.strokeEllipse(in: box.insetBy(dx: cell * 0.055, dy: cell * 0.055))
                }
            }
            let ink = light ? MTChessPalette.dark : MTChessPalette.light
            let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: max(10, cell * 0.16), weight: .semibold), .foregroundColor: ink]
            if col == 0 { (String(sq / 8 + 1) as NSString).draw(at: box.origin.applying(.init(translationX: 3, y: 2)), withAttributes: attributes) }
            if row == 7 {
                (String(MTChessPosition.square(sq).prefix(1)) as NSString)
                    .draw(at: CGPoint(x: box.maxX - cell * 0.18, y: box.maxY - cell * 0.2), withAttributes: attributes)
            }
        } }
    }
}
