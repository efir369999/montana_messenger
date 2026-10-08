/// A stable, bounded selection: newest first, preserving traversal order for equal timestamps.
/// Storage never exceeds the result limit, even when every message matches.
struct MTNewestMatches<Element> {
    private let limit: Int
    private var ranked: [(time: Double, value: Element)] = []
    init(limit: Int) { self.limit = max(0, limit) }
    var values: [Element] { ranked.map(\.value) }
    var count: Int { ranked.count }
    mutating func insert(_ value: Element, time: Double) {
        guard limit > 0 else { return }
        let time = time.isFinite ? time : -Double.greatestFiniteMagnitude
        var low = 0, high = ranked.count
        while low < high {
            let middle = (low + high) / 2
            if ranked[middle].time >= time { low = middle + 1 } else { high = middle }
        }
        guard low < limit else { return }
        // Remove before inserting so the allocation remains bounded even at capacity.
        if ranked.count == limit { ranked.removeLast() }
        ranked.insert((time, value), at: low)
    }
}
