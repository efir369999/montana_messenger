import Foundation
import CryptoKit
import UIKit
import MontanaBindings

/// Reputation is always visible (14.10.2026). The old preference is retained only
/// for reading backups; it no longer suppresses sending or drawing the level.
enum MTLevelShow {
    static let shownKey = "level.shown"   // COMPAT-LOCAL: retired preference
    static var on: Bool { true }
}

/// THE PERSON'S LEVEL FOR A WORD SAID FROM ANY THREAD (11.10.2026, E2E.levelTail): the presence words are built off the main actor,
/// where the chain of the person lives. The chain writes its level here at every count; nil until this life read its seconds, so
/// an unknown level is never said as none.
enum MTPersonLevel {
    private static let lock = NSLock()
    private static var held: Int?
    static var now: Int? { lock.lock(); defer { lock.unlock() }; return held }
    static func set(_ v: Int?) { lock.lock(); held = v; lock.unlock() }
}

/// THE PERSON'S GLOBAL LEVEL AS THIS PHONE LAST KNEW IT. No function of the app waits for a level (the author's word 16165,
/// 04.11.2026: «remove every condition of level 7 from the Protocol app, and every menu of access by level too»; decision 606 (a):
/// one's own node opens on every level, its row straight in Settings): a deletion for everyone always lands, a call is recorded by
/// the person's own switch and the call screen's mark, and one's own node stands wherever the edition carries it (MTEdition.ownNode).
/// The level is still said in a call's caps (MontanaCall.myCaps) for the builds that read it, where the edition carries levels
/// (MTEdition.levels: Messenger carries none, decision 618 (b)); before this life has read it, the last one this phone knew stands.
enum MTLevelAccess {
    static let lastKey = "levelAccess.last"                    // NOT-UI: the last Global Level this phone knew of this person
    static var level: Int? {
        guard let p = MTPersonLevel.now, let w = MTPersonChain.walletTerm else { return UserDefaults.standard.object(forKey: lastKey) as? Int }
        let g = MTPersonChain.global(person: p, wallet: w)
        if UserDefaults.standard.object(forKey: lastKey) as? Int != g { UserDefaults.standard.set(g, forKey: lastKey) }
        return g
    }
}

/// The public distribution contains counts of levels only. A separate, seed-derived
/// owner token lets each person replace their own level without publishing a balance,
/// name, address or contact list. Old clients can continue using every existing door.
@MainActor final class MTLevelDistribution: ObservableObject {
    static let shared = MTLevelDistribution()
    struct Bin: Codable, Equatable { let level: Int; let count: Int }
    @Published private(set) var bins: [Bin] = []
    private var asking = false
    private var again = false
    private var published: String?
    private var publishedAt = Date.distantPast
    private var attemptedAt = Date.distantPast
    private var readAt = Date.distantPast
    nonisolated static let cacheKey = "level.distribution"
    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.cacheKey), let kept = try? JSONDecoder().decode([Bin].self, from: data) {
            bins = Self.valid(kept)
        }
    }
    static func valid(_ input: [Bin]) -> [Bin] {
        let clean = input.filter { (0...62).contains($0.level) && (1...1_000_000).contains($0.count) }
        guard Set(clean.map(\.level)).count == clean.count, clean.count <= 63 else { return [] }
        return clean.sorted { $0.level < $1.level }
    }
    static func rank(_ level: Int, in bins: [Bin]) -> Double? {
        guard let first = bins.first, let last = bins.last else { return nil }
        if first.level == last.level { return level < first.level ? 0 : 1 }
        if level <= first.level { return 0 }
        if level >= last.level { return 1 }
        let total = bins.reduce(0.0) { $0 + Double($1.count) }
        let before = bins.filter { $0.level < level }.reduce(0.0) { $0 + Double($1.count) }
        let same = Double(bins.first { $0.level == level }?.count ?? 0)
        let low = Double(first.count) / 2, high = total - Double(last.count) / 2
        return max(0, min(1, (before + same / 2 - low) / (high - low)))
    }
    func rank(_ level: Int) -> Double? { Self.rank(level, in: bins) }
    private func own() -> (token: String, level: Int)? {
        guard let person = MTPersonLevel.now, let wallet = MTPersonChain.walletTerm,
              let words = MontanaSeed.mnemonic, let entropy = MontanaSeedKeys.entropyFrom(mnemonic: words) else { return nil }
        let key = HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: entropy), salt: Data(),
            info: Data("mt-level-distribution-v1".utf8), outputByteCount: 32)
        let token = Data(HMAC<SHA256>.authenticationCode(for: Data("owner".utf8), using: key))
        return (MontanaHomeNode.hex(token), MTPersonChain.global(person: person, wallet: wallet))
    }
    func changed() {
        guard MTEdition.levels, let own = own(), published != own.token + ":" + String(own.level) else { return }
        Task { await refresh() }
    }
    func refresh() async {
        guard MTEdition.levels else { return }   // an edition without levels publishes and reads none (decision 618 (b))
        if asking { again = true; return }
        let own = own(), stamp = own.map { $0.token + ":" + String($0.level) }
        let needsPut = stamp != nil && (stamp != published || Date().timeIntervalSince(publishedAt) >= 300)
        guard Date().timeIntervalSince(attemptedAt) >= 5, needsPut || Date().timeIntervalSince(readAt) >= 60 else { return }
        attemptedAt = Date()
        asking = true
        defer {
            asking = false
            if again { again = false; Task { await refresh() } }
        }
        for base in MontanaWakePush.orderedBases(for: "levels").prefix(3) {
            if needsPut, let own {
                if await post(base + "/level-put", body: ["token": own.token, "level": own.level]) != nil { published = stamp; publishedAt = Date() }
            }
            guard let reply = await post(base + "/level-get", body: [:]),
                  let rows = reply["levels"] as? [[String: Int]] else { continue }
            let next = Self.valid(rows.compactMap { row in
                guard let level = row["level"], let count = row["count"] else { return nil }
                return Bin(level: level, count: count)
            })
            if bins != next {
                bins = next
                if let data = try? JSONEncoder().encode(next) { UserDefaults.standard.set(data, forKey: Self.cacheKey) }
            }
            readAt = Date()
            MontanaTrace.markChanged("level_distribution", "bins=\(next.count)")
            return
        }
    }
    private func post(_ word: String, body: [String: Any]) async -> [String: Any]? {
        guard let url = URL(string: word), let data = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        var request = URLRequest(url: url); request.httpMethod = "POST"; request.timeoutInterval = 6
        request.setValue("application/json", forHTTPHeaderField: "Content-Type"); request.httpBody = data
        guard let (reply, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200, reply.count <= 32_768 else { return nil }
        return (try? JSONSerialization.jsonObject(with: reply)) as? [String: Any]
    }
}
