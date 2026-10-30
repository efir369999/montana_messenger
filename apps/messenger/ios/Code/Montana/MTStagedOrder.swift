//
//  MTStagedOrder.swift -- the order a tray above the field leaves in (25.10.2026).
//

import Foundation

/// THE ORDER CHOSEN IS THE ORDER SENT (the author's word 25.10.2026 17:40 UTC, council link 8089: «when a file is added, the
/// choosing form shows the numeric order, with many chosen at once, and the upload into a chat, a channel, a group follows the
/// order of the files chosen -- I asked before and it does not work: it adds one file at a time»). What waits above the field
/// wears its place, 1, 2, 3; a cross takes one out and the numbers close up, because the number IS the place in the one array
/// every staging road lands in. The rules of the order live here, apart from the screen, so a check compiles them alone
/// (tools/mt-stage-order-check.py).
enum MTStagedOrder {
    /// What a staged item is to the order: a picture folds into a plate with its neighbours, a sticker and a file stand alone.
    enum Kind { case picture, sticker, file }

    /// The number a place wears: one more than its index, so taking one out closes the numbers up by construction.
    static func number(at index: Int) -> Int { index + 1 }

    /// THE PERSON SETS THE ORDER (the author's words 27.10.2026 09:16 UTC, council links 9562-9563: «they are loaded into the message
    /// field in the wrong order already and cannot be changed»): the platform's Files page hands its files back in its own order and
    /// numbers nothing, so the tray is where the order is set. A plate carried from `from` stands at `to`; every other keeps its turn,
    /// and the numbers follow by construction (number(at:)). A place outside the tray changes nothing.
    static func moved<T>(_ items: [T], from: Int, to: Int) -> [T] {
        guard items.indices.contains(from), items.indices.contains(to), from != to else { return items }
        var a = items
        a.insert(a.remove(at: from), at: to)
        return a
    }

    /// THE PLATES OF A TRAY (19.09 for pictures, 25.10 for files among them): pictures side by side fold into one plate; a file
    /// between them ends the run, so the feed stands pictures and files in the very order chosen and never pulls a plate across
    /// a file. A tray that holds a sticker folds nothing, as before (a sticker never folds). Only a run of two or more is a plate.
    static func plates(_ kinds: [Kind]) -> [Range<Int>] {
        if kinds.contains(.sticker) { return [] }
        var out: [Range<Int>] = []
        var start: Int? = nil
        for (i, k) in kinds.enumerated() {
            if k == .picture {
                if start == nil { start = i }
            } else if let s = start {
                if i - s > 1 { out.append(s..<i) }
                start = nil
            }
        }
        if let s = start, kinds.count - s > 1 { out.append(s..<kinds.count) }
        return out
    }
}

/// ONE LINE OUT PER CONVERSATION (the author's word 25.10.2026 17:40 UTC, council link 8089): a file never overtakes an earlier
/// one, whatever their sizes and upload times. Every send of a tray stands in its conversation's line and starts when the one
/// before it is over -- uploaded, refused, or left to the drain -- so the receiver gets them in the order chosen, not in the
/// order the network happened to finish them. The rows are laid at once (the bubble is local and instant, 18.09); only the
/// network work waits its turn. The word of 20.09 («no gate, no slot», sendMediaToPeer) stands for every other road: this
/// line holds what a tray sends, and nothing else.
@MainActor
final class MTSendLine {
    static let shared = MTSendLine()
    private var tails: [String: Task<Void, Never>] = [:]   // the last send standing in each line
    private var waiting: [String: Int] = [:]               // the sends of each line not over yet

    /// `turn` starts one send and returns when its network work is over; it begins after every turn queued before it.
    func enqueue(_ line: String, _ turn: @escaping @MainActor () async -> Void) {
        let before = tails[line]
        waiting[line, default: 0] += 1
        tails[line] = Task { @MainActor in
            await before?.value
            await turn()
            self.waiting[line, default: 1] -= 1
            if self.waiting[line] == 0 { self.waiting[line] = nil; self.tails[line] = nil }
        }
    }
    /// How many sends of the line are not over yet (the trace's word).
    func pending(_ line: String) -> Int { waiting[line] ?? 0 }
}
