import SwiftUI
import UIKit

/// One policy for scrolling, message arrival and reply return. UIKit owns the scroll offset.
enum MTLetterMotion {
    static let bounceKey = "chatSpringBounce"
    static let durationKey = "chatSpringDuration"
    static let defaultBounce = 0.18
    static let defaultDuration = 0.55
    static let bounceRange = 0.0...0.4
    static let durationRange = 0.25...0.8
    static let rise: CGFloat = 0.9

    // Copies from older builds or malformed preferences cannot create an unstable animation.
    static func bounded(_ value: Double, in range: ClosedRange<Double>, fallback: Double) -> Double {
        value.isFinite ? min(range.upperBound, max(range.lowerBound, value)) : fallback
    }
    private static func read(_ key: String, in range: ClosedRange<Double>, fallback: Double) -> Double {
        guard let value = UserDefaults.standard.object(forKey: key) as? NSNumber else { return fallback }
        return bounded(value.doubleValue, in: range, fallback: fallback)
    }
    static var duration: TimeInterval { read(durationKey, in: durationRange, fallback: defaultDuration) }
    static var bounce: Double { read(bounceKey, in: bounceRange, fallback: defaultBounce) }
    static var fade: TimeInterval { min(0.28, duration / 2) }
    static var reply: Animation {
        UIAccessibility.isReduceMotionEnabled ? .linear(duration: 0) : .spring(duration: duration, bounce: bounce)
    }
    static func animate(_ changes: @escaping () -> Void) {
        guard !UIAccessibility.isReduceMotionEnabled else { changes(); return }
        UIView.animate(springDuration: duration, bounce: CGFloat(bounce), initialSpringVelocity: 0,
                       delay: 0, options: [.allowUserInteraction, .beginFromCurrentState], animations: changes)
    }
}

/// Only visible row content rides a native spring; layout, hit targets and keyboard insets stay native.
@MainActor
final class MTFeedSpring {
    private final class Item: NSObject, UIDynamicItem {
        weak var content: UIView?
        var center = CGPoint.zero {
            didSet { content?.transform = CGAffineTransform(translationX: 0, y: center.y) }
        }
        let bounds = CGRect(x: 0, y: 0, width: 1, height: 1)
        var transform = CGAffineTransform.identity
        init(content: UIView) { self.content = content }
    }
    private struct Row {
        let item: Item
        let spring: UIAttachmentBehavior
    }
    private weak var collection: UICollectionView?
    private let animator = UIDynamicAnimator()
    private var rows: [ObjectIdentifier: Row] = [:]
    private var previousY: CGFloat = 0
    private var fingerY: CGFloat = 0
    private var bounce = 0.0
    private var duration = MTLetterMotion.defaultDuration

    init(collection: UICollectionView) { self.collection = collection }

    func begin() {
        reset()
        guard let collection else { return }
        previousY = collection.contentOffset.y
        bounce = UIAccessibility.isReduceMotionEnabled ? 0 : MTLetterMotion.bounce
        duration = MTLetterMotion.duration
        fingerY = collection.panGestureRecognizer.location(in: collection).y - previousY
    }

    func reset() {
        animator.removeAllBehaviors()
        for row in rows.values { row.item.content?.transform = .identity }
        rows.removeAll(keepingCapacity: true)
        previousY = collection?.contentOffset.y ?? 0
    }

    func remove(_ cell: UICollectionViewCell) {
        guard let row = rows.removeValue(forKey: ObjectIdentifier(cell)) else { return }
        animator.removeBehavior(row.spring)
        row.item.content?.transform = .identity
    }

    func scroll(enabled: Bool) {
        guard let collection else { return }
        let y = collection.contentOffset.y
        let delta = y - previousY
        previousY = y
        guard enabled, bounce > 0, !UIAccessibility.isReduceMotionEnabled,
              collection.window != nil, UIApplication.shared.applicationState == .active,
              collection.isDragging || collection.isDecelerating else { reset(); return }
        guard abs(delta) > 0.01 else { return }
        if collection.isDragging {
            fingerY = collection.panGestureRecognizer.location(in: collection).y - y
        }
        let cells = collection.visibleCells
        let visible = Set(cells.map { ObjectIdentifier($0) })
        for key in rows.keys.filter({ !visible.contains($0) }) {
            if let row = rows.removeValue(forKey: key) {
                animator.removeBehavior(row.spring)
                row.item.content?.transform = .identity
            }
        }
        for cell in cells where cell.bounds.height > 8 {
            let key = ObjectIdentifier(cell)
            let row: Row
            if let existing = rows[key] { row = existing }
            else {
                let item = Item(content: cell.contentView)
                let spring = UIAttachmentBehavior(item: item, attachedToAnchor: .zero)
                spring.length = 0
                spring.damping = CGFloat(1 - bounce)
                spring.frequency = CGFloat(1 / duration)
                row = Row(item: item, spring: spring)
                rows[key] = row
                animator.addBehavior(spring)
            }
            let distance = abs(cell.center.y - y - fingerY)
            let resistance = min(1, distance / max(1, collection.bounds.height)) * CGFloat(bounce)
            let limit = min(14, cell.bounds.height * 0.15)
            row.item.center.y = min(limit, max(-limit, row.item.center.y + delta * resistance))
            animator.updateItem(usingCurrentState: row.item)
        }
    }
}
