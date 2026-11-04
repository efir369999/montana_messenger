import Foundation
import CryptoKit
import UIKit
import MontanaBindings

// A reader of the protocol boundary. Missing state stays missing: zero is shown only when
// mtc_wallet_balance actually returns it. This reader never creates a test network or a person.
enum MTWalletCore {
    enum Absence: Error, Sendable { case unavailable, device, person, refused }
    struct Window: Identifiable, Sendable {
        let id: UInt64
        let share: UInt64
        let acceptedIn: UInt64
    }
    struct Snapshot: Sendable {
        let balance: String
        let notes: Int
        let lastConfirmedWindow: UInt64?
        let pulseRunning: Bool
        let windows: [Window]
    }
    static func read() -> Result<Snapshot, Absence> {
        #if MONTANA_PROTOCOL_CORE
        var standing: Int32 = 0
        guard mtc_device_standing(&standing) == 0 else { return .failure(.refused) }
        guard standing == 1 else { return .failure(.device) }
        guard mtc_person_stands(&standing) == 0 else { return .failure(.refused) }
        guard standing == 1 else { return .failure(.person) }
        var bytes = [UInt8](repeating: 0, count: 16)
        var notes = 0, present: Int32 = 0, head: UInt64 = 0, running: Int32 = 0, count = 0
        guard mtc_wallet_balance(&bytes) == 0, mtc_wallet_notes(&notes) == 0,
              mtc_machine_head(&head, &present) == 0, mtc_pulse_running(&running) == 0,
              mtc_pulse_lived(&count) == 0 else { return .failure(.refused) }
        var windows: [Window] = []
        // A bounded view of core receipts; the core retains the source. Nothing here mints.
        for i in max(0, count - 100)..<count {
            var window: UInt64 = 0, rounds: UInt32 = 0, living = 0, share: UInt64 = 0, accepted: UInt64 = 0
            guard mtc_pulse_lived_at(i, &window, &rounds, &living, &share, &accepted) == 0 else { return .failure(.refused) }
            windows.append(.init(id: window, share: share, acceptedIn: accepted))
        }
        return .success(.init(balance: decimal(bytes), notes: notes, lastConfirmedWindow: present == 1 ? head : nil,
                              pulseRunning: running == 1, windows: Array(windows.reversed())))
        #else
        return .failure(.unavailable)
        #endif
    }
    // Formatting the core's u128 little-endian value, without floating-point rounding.

    static func said(_ absence: Absence?) -> String {
        switch absence {
        case .unavailable: return String(localized: "The protocol core is unavailable on this device.", bundle: MTLanguage.bundle)
        case .device: return String(localized: "The protocol device has not joined the network.", bundle: MTLanguage.bundle)
        case .person: return String(localized: "The core has not opened your wallet.", bundle: MTLanguage.bundle)
        case .refused: return String(localized: "The core could not confirm the wallet state. Try refreshing.", bundle: MTLanguage.bundle)
        case nil: return String(localized: "Reading the wallet…", bundle: MTLanguage.bundle)
        }
    }

    static func decimal(_ bytes: [UInt8]) -> String {
        var digits = [0]
        for byte in bytes.reversed() {
            var carry = Int(byte)
            for i in digits.indices {
                let next = digits[i] * 256 + carry
                digits[i] = next % 10; carry = next / 10
            }
            while carry > 0 { digits.append(carry % 10); carry /= 10 }
        }
        return digits.reversed().map(String.init).joined()
    }
}

/// THE CHAT'S COINS, READ AS HISTORY (the author's words 02.10 18:29-19:37 began them: «every letter drips one billionth of a
/// Montana to the person, equal to one coin»). Up to the time cut a letter of a pair's ribbon earned a coin in this phone's book by
/// its wire name; from 22.10.2026 21:00 UTC only the chain mints (fold-6, fold-7), and since build 2320 no letter, bubble or feed
/// asks the book at all (the author's decision 375 «a», 29.10.2026 22:01 UTC: the dead local minting removed, the old lines read
/// as history; the word 11871: «only the rule of the constitution, 1 coin is 1 second, by the core»). What stands is the wire
/// name those coins were booked by and the coin's reading in Montana.
enum MTChatMint {
    /// One coin is one billionth of a Montana (the author's word 02.10 19:37).
    static let coinsPerMontana = 1_000_000_000

    /// «mid:t» + birth millisecond + «-» + a uuid: the name a sender mints (ChatStore.mintMid).
    static func wireName(_ s: String) -> Bool {
        s.hasPrefix("mid:t") && s.count == 5 + String(s.dropFirst(5).prefix { $0 != "-" }).count + 37
            && UUID(uuidString: String(s.suffix(36))) != nil
    }

    /// The coins as Montana, in integers alone: one coin is 0.000000001.
    static func montana(_ coins: Int) -> String {
        let whole = coins / coinsPerMontana, part = coins % coinsPerMontana
        let digits = String(part)
        return MTCoinText.count(whole) + "." + String(repeating: "0", count: 9 - digits.count) + digits
    }
}

/// BIG NUMBERS PART THEIR THOUSANDS WITH COMMAS (the author's word 04.10.2026 01:20 UTC: «the separators of big numbers are
/// commas»): in every language of the phone, the one owner of how a count of coins reads -- 1,234,567.
enum MTCoinText {
    static func count(_ n: Int) -> String {
        let digits = String(n.magnitude)
        var out = ""
        for (i, d) in digits.enumerated() {
            if 0 < i, (digits.count - i) % 3 == 0 { out.append(",") }
            out.append(d)
        }
        return (n < 0 ? "-" : "") + out
    }
}

/// THE CHAINS OF THE COINS (slice S2b b7f): which chain a move of coins joins, by its name and kind, and the moves joining them --
/// the coins' own reading of the TimeChains of the minting (MTTimeChain), which keeps the chains themselves.
extension MTTimeChain {
    static func source(of e: MTCoinEntry) -> String { source(ref: e.ref, kind: e.k, peer: e.peer) }
    static func source(ref r: String, kind: MTCoinEntry.Kind, peer: String? = nil) -> String {
        source(ref: r, kind: kind, peer: peer) { p in MTGroup.shared.kind(p) == .channel }
    }
    /// The same reading with the channels said by the caller: a fold off the screen's thread asks no live group (MTCoinHistory).
    static func source(ref r: String, kind: MTCoinEntry.Kind, peer: String?, channel: (String) -> Bool) -> String {
        if MTCoinLegacy.chess(r) { return "chess" }   // the book's chess lines of the builds before (MTCoinLegacy)
        if r.hasPrefix(MTPantheon.refPrefix) { return "pantheon" }
        if r.hasPrefix(MTVPNWallMint.refPrefix) { return "vpnwall" }
        if let p = MTApps.vpn?.payRefPrefix, r.hasPrefix(p) { return "vpnpay" }
        if MTCoinLegacy.call(r) { return "calls" }
        if MTCoinLegacy.timer(r) { return "timer" }
        if MTBoardCoins.owns(r) { return "comments" }
        switch kind {
        case .earn:
            // A GROUP'S AND A CHANNEL'S COINS STAND IN THEIR OWN CHAINS (the author's words 06.10.2026 08:5x-09:0x UTC: «their own
            // TimeChain and their own app»): the letter's conversation names its chain.
            guard let p = peer, MTGroup.isKey(p) else { return "chats" }
            return channel(p) ? "channels" : "groups"
        case .receive: return "received"
        case .spend: return "spent"
        case .send: return "sent"
        case .burn: return r.hasPrefix(MTCoinBurn.callPrefix) ? "calls" : "letters"
        }
    }
    /// One move of coins joins its source's chain, once by its name, in the order the moves were written.
    static func append(_ e: MTCoinEntry) { note(source(of: e), kind: e.k.rawValue, coins: e.c, ref: e.ref, at: e.at) }
    /// The book's whole past in one turn of the queue, not a turn for every move (04.10).
    static func appendPast(_ moves: [MTCoinEntry]) {
        let links = moves.map { e in (chain: source(of: e), kind: e.k.rawValue, coins: e.c, ref: e.ref, at: e.at) }
        notePast(links)
    }
}

/// THE THIRTEEN BOXES OF π (the author's words 03.10 21:59-22:02: «boxes by the number π, ascending by share of emission, the
/// top thirteen»; «on the coin's badge your number in the rating»; «when sending, the same thirteen boxes in the reaction»;
/// «a table of the top thirteen in the wallet by a button»). Box n holds the first n digits of π as whole coins -- 3, 31,
/// 314 … 3 141 592 653 589 -- each a share of a Montana (a Montana is a billion coins). A balance's place is the number of
/// boxes it fills, read on this phone from its own book; the same boxes are the amounts a person gives.
/// LEVELS BY PI (the author's word 04.10.2026 09:23 UTC: «call them levels by pi instead of boxes; if I am of level 5, all my
/// minting everywhere is counted by one function of the level's multiplier»): the boxes of 03.10 are the levels of π, and
/// `multiplier` is the one function every minting asks -- the book applies it to every earning and every minting.
enum MTPiLevels {
    /// THE LEVELS HAVE NO BORDER BUT THE INTEGER'S (the author's word 04.10 00:51: «the wallet's level is defined so, without
    /// borders, 13 always»): nineteen digits of π, the most a count of coins holds; the wallet shows thirteen of them at a time.
    static let digits = MTFabricRules.piDigits
    static let all: [Int] = MTFabricRules.piPrefixes
    /// How many levels stand on the page at once.
    static let shown = 13
    /// The number of levels the balance fills: 0 below the first.
    static func place(_ balance: Int) -> Int { MTFabricRules.walletLevel(balance) }
    /// THE LEVEL IS A READING, NEVER A RATE (the constitution of the chain, point 11; the author's words 19.10.2026 12:3x UTC: «this
    /// is the ceiling, the invariant -- nothing else can mint or accelerate it, no music, no VPN and so on»; «the Global Level is
    /// untied from the minting»; 13:4x: «bring it all to one owner of the function 1 coin = 1 second, and that is all»): the one
    /// owner of a second's coin is the book (MTCoinBook.price, MTLocalCoinLedger.priced); a level multiplies nothing.
    /// π as far as a level reveals it: 3, 3.1, 3.14 ...
    static func revealed(_ place: Int) -> String {
        let d = String(digits.prefix(max(0, place)))
        return d.count < 2 ? d : String(d.prefix(1)) + "." + String(d.dropFirst())
    }
    /// Coins in the short form the author named (03.10 21:19: «1k, 10k, 100k and so on up to a whole Montana, 1kkk», the k in the person's language): whole
    /// thousands, millions and billions, never rounded up -- the badge says at least what is held.
    static func short(_ n: Int) -> String {
        max(0, n).formatted(.number.notation(.compactName).precision(.fractionLength(0...1)).locale(MTLanguage.locale))
    }
}

/// THE COINS RISE AT THE SIDES (the author's words 03.10.2026 21:11 UTC: «auto minting one coin a second with an animation at
/// the sides»; «at a chess move the coins' animation too»): the one owner of the minting's sign. The chain's seconds tell it as
/// they come (MTCoinSplit.beat) -- a coin rises only when the chain credits it -- and
/// every screen that wears the sides (MTCoinSides) shows the same coins rising at both edges with the count.
/// ONE RISE, THE SUM (the author's word 04.10.2026 15:08 UTC, T2: «the minting's animation must not double, only give the sum in
/// the plus animation»; T2's diary 15:10Z: the pull's +5 and the VPN wall's +5 rose apart every second -- the first coin rose at
/// once and the coins after it rose again half a second later): while the minting by the second beats (MTMintBeat), the beat
/// alone raises the coins, once a second, with the sum of everything minted in that second; without it the coins gather a fifth
/// of a second and rise once, twice a second at most (the heat, 04.10 12:27).
/// NO ICON OF THE APP THAT MINTS (the author's word 02.11.2026 18:19 UTC, link 14775: «under the words Pantheon on Fire remove the
/// icons of the wallet and the VPN»): only the chain's seconds are born here (link 14629), and the page names no app beside them.
@MainActor final class MTCoinFlash: ObservableObject {
    static let shared = MTCoinFlash()
    @Published private(set) var tick = 0
    @Published private(set) var coins = 0
    static let gather: Double = 0.2
    static let apart: Double = 0.5
    private var held = 0
    private var gathering = false
    private var rose: Double = 0
    func born(_ n: Int) {
        guard 0 < n else { return }
        let now = Date().timeIntervalSince1970
        held += n
        guard !MTMintBeat.beats, !gathering else { return }
        gathering = true
        let wait = max(Self.gather, rose + Self.apart - now)
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            self?.rise()
        }
    }
    /// The coins held rise now, with their sum; the beat calls it once a second.
    func rise() {
        gathering = false
        if 0 < held {
            coins = held
            held = 0
            rose = Date().timeIntervalSince1970
            tick += 1
        }
    }
}

/// PANTHEON ON FIRE (the author's word 03.10.2026 19:25 UTC: «a tap on the coin in the wallet is +1 too, quick taps all count;
/// the coin spins at a speed from 1 to 13 and the speed is shown; the game is called Pantheon on Fire, the first tap on the
/// wallet's coin lights it»). Since build 2320 a tap mints nothing (the author's decision 375 «a»: only the chain mints, 1 coin is
/// 1 second); the fire and the coin's turn are the game alone. The speed is the taps of the last second, up to thirteen. The speed falls to zero
/// when the taps stop: the number shows the taps, it never holds them.
@MainActor final class MTPantheon: ObservableObject {
    static let shared = MTPantheon()
    static let ceiling = 13
    /// The name a tap's coin stood under in the books of the builds before 2320, read as history.
    nonisolated static let refPrefix = "tap:"
    @Published private(set) var lit = false
    @Published private(set) var speed = 0
    private var taps: [Double] = []
    private var holding = false
    /// THE FIRE RESTS AFTER A MINUTE (the author's word 04.10.2026 10:38 UTC: «at the Pantheon on Fire's activation, under the level's
    /// progress, a progress of the minting's unbroken run too; when it runs unbroken over 60 seconds, the next 60 the minting
    /// pauses»): a burn counts its seconds from its lighting; at sixty the fire goes out and the coin rests sixty -- no tap mints --
    /// and the next burn counts anew. The quiet that puts the fire out breaks the count; since link 14773 no line draws it.
    static let streak: Double = 60
    @Published private(set) var litAt: Double?
    @Published private(set) var restUntil: Double?
    private var resting: Task<Void, Never>?
    var rests: Bool { restUntil.map { Date().timeIntervalSince1970 < $0 } ?? false }
    private func light() {
        guard !lit, !rests else { return }
        lit = true
        let at = Date().timeIntervalSince1970
        litAt = at
        MontanaTrace.mark("pantheon", "lit")
        resting?.cancel()
        resting = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.streak * 1_000_000_000))
            guard !Task.isCancelled, let self, self.litAt == at else { return }
            self.rest()
        }
    }
    private func rest() {
        going?.cancel()
        lit = false; litAt = nil; speed = 0; taps = []
        let until = Date().timeIntervalSince1970 + Self.streak
        restUntil = until
        MontanaTrace.mark("pantheon", "rest")
        resting = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.streak * 1_000_000_000))
            guard !Task.isCancelled, let self, self.restUntil == until else { return }
            self.restUntil = nil
            MontanaTrace.mark("pantheon", "rested")
        }
    }
    private var settling: Task<Void, Never>?
    private var going: Task<Void, Never>?
    /// THE FIRE GOES OUT IN THREE SECONDS OF QUIET (the author's word 04.10.2026 00:13 UTC: «if you do not mint for 3 seconds, switch the
    /// Pantheon on Fire off»; before it, a minute, 03.10 21:19): while it burns the wallet's page does not scroll at all.
    static let quiet: UInt64 = 3

    /// A finger landed on the coin: the game lights at the touch itself, so the page stands from the first finger, before its coin.
    /// THE FIRE BURNS WHILE A FINGER HOLDS THE COIN (the author's word 04.10.2026 10:06 UTC: «if I press and hold the coin in the
    /// wallet, do not switch the Pantheon on Fire off, and after the seconds switch the auto minting on»): on T1 the fire went out
    /// at the third second of a held finger, the finger left at the fourth and the ninth never came. The quiet counts from the
    /// last finger's lift.
    func touched() {
        holding = true
        light()
        going?.cancel()
    }
    /// The last finger left the coin -- or the page left under it, which the platform need not tell the coin (MTWalletScreen).
    func released() {
        guard holding else { return }
        holding = false
        goOutAfterQuiet()
    }
    /// One touch of the coin: it lights the fire and counts the finger's speed up to thirteen touches -- never a coin (decision 375 «a»).
    func tap() {
        let now = Date().timeIntervalSince1970
        taps.removeAll { 1 <= now - $0 }
        guard !rests else { return }
        light()
        if !holding { goOutAfterQuiet() }
        guard taps.count < Self.ceiling else { return }
        taps.append(now)
        speed = taps.count
        settle()
    }

    private func goOutAfterQuiet() {
        going?.cancel()
        going = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.quiet * 1_000_000_000)
            guard !Task.isCancelled, let self, self.lit else { return }
            self.lit = false
            self.litAt = nil
            self.resting?.cancel()
            MontanaTrace.mark("pantheon", "out after quiet")
        }
    }

    /// The speed reads the last second again ten times a second until no tap is left in it.
    private func settle() {
        settling?.cancel()
        settling = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 100_000_000)
                guard let self else { return }
                let now = Date().timeIntervalSince1970
                self.taps.removeAll { 1 <= now - $0 }
                self.speed = self.taps.count
                if self.taps.isEmpty { return }
            }
        }
    }
}

/// THE BURNS OF THE BUILDS BEFORE (the author's words 03.10.2026 21:51-22:01 UTC): up to build 2111 a call burned its seconds and a
/// letter one coin. The author's words 04.10.2026 22:21-22:31 UTC turned the burn into a payment to the person -- «the one who calls
/// pays the one called, the one who writes pays the one written to» (MTCoinSend.pay); a call moves no coin (the author's word 29.10.2026 19:31 UTC).
/// The names stay to read
/// the burns the books already hold.
enum MTCoinBurn {
    static let callPrefix = "call:"
    static let letterPrefix = "letter:"
}

/// THE BOOK'S BALANCE FOR A READER OFF THE MAIN ACTOR (03.10): the word about oneself is built on the delivery's own threads,
/// and the book lives on the main actor. The book writes its balance here at every move; until it has read its file this holds
/// nothing, so the word never tells a pair a balance of nothing it does not hold.
enum MTCoinBalance {
    private static let lock = NSLock()
    private static var held: Int?
    static var now: Int? { lock.lock(); defer { lock.unlock() }; return held }
    static func set(_ v: Int) {
        lock.lock(); let moved = held != v; held = v; lock.unlock()
        if moved { Task { @MainActor in MTCoinTell.moved(); MTFabric.shared.refresh(); MTLevelDistribution.shared.changed() } }
    }
}

/// THE COINS BEHIND THEIR DOOR (MTApps.coins, docs/APPS-API.md): what this application answers shared code.
final class MTCoinsDoor: MTCoinDoor {
    var walletLevel: Int? { MTCoinBalance.now.map(MTFabricRules.walletLevel) }
    var chainsBefore: URL? { MTCoinPlace.dir }
    var settingKeys: [String] {
        [MTCoinShow.key, MTCoinShow.toldKey,   // the owner shows or hides their coins, and the wallet has said what that does (04.10)
         "avatarBadges.coins",   // COMPAT-LOCAL: the retired viewer switch, retained for old copies (14.10); the balance owner alone governs disclosure
         MTPersonalRate.key,   // the person's earning, its period and currency: their own rate of the coin (04.10 19:19)
         MTCoinUnit.mainKey]   // the sum of the balance the person made the main one: time, coins or the ticker (19.10.2026)
    }
    var seatKeys: [String] {
        [MTCoinBoard.key, MTCoinBoard.levelsKey]   // the balances and the Global Levels this person's correspondents told: learned for this person
    }
    var seatFolders: [String] {
        ["AS:Montana/Coins"]   // the person's coin book and the chats' tally (MTCoinPlace): parked with the person, never another's (T2 19.10.2026)
    }
    @MainActor func moment(_ m: MTAppMoment) {
        switch m {
        case .launching: MTTopNet.noteFirstLaunch()   // whether an earlier build had published this device's top row (5.1.2(i), 08.10.2026)
        case .launched: MTLocalCoinLedger.warm()   // read off the main thread from here, so the wallet opens on the frame of the touch (04.10 13:04)
        case .active:
            MTVPNWallMint.count()   // the VPN wall's seconds are counted at the return (03.10)
            MTCoinVault.shared.soon("active", after: 1)   // the seed's other devices, gathered at the return (04.10)
            Task { await MTTimeChainTip.shared.gather(why: "active") }   // their tips first, in one round trip (04.10 16:34)
        case .tunnelConnected: MTVPNWallMint.count()
        // The coins of the person leaving are on disk in their own folder before it moves (the coin audit's fourth point), and
        // no walk of the chain begun under them writes from this turn on (MTCoinSeat, the critic 19.10.2026 on T2).
        case .seatLeaving: MTLocalCoinLedger.shared.writeWhole()   // the seat's turn moves right after (MTSeatTurn.leaving)
        // The coin book of the person forgotten is on disk whole and set aside before anything of theirs leaves (the coin
        // audit's eighth point); with other seats the seat's own road parks it (MTSeats.leaveForgotten).
        case .forgottenAlone: MTLocalCoinLedger.shared.writeWhole(); MTCoinPlace.setAside()
        case .seated: MTCoinBook.reread()   // the seated person's own coins, never the book of the one who left (04.10)
        // THE IDENTITY LEAVES THE NODES TOO (App Review 5.1.1(v), 08.10.2026: deleting an account deletes its records): the row of
        // the Montana top -- the name and the coins shown -- is withdrawn from every node while the words still derive its token.
        case .seedForgetting: MTTopNet.shared.withdraw()
        case .shown, .returned, .hidden: break   // the VPN's own moments (slice S3b b1)
        case .transfersAsked: MTCoinHistory.shared.warm()   // the coins' fold, once, at a person's transactions tab
        }
    }
    // MY COIN KEY RIDES THE WORD ABOUT MYSELF (COIN-TX-V3 section 1; the author's word 21.10.2026 09:41 UTC): a key not derived
    // yet is derived off the main thread now, and the whole book hears it when it stands (MTCoinTx.deriveForTheWord).
    // THE BALANCE RIDES THE SAME WORD (03.10, MTCoinBoard): told again when it changed, once in ten minutes at most.
    // HIDDEN IS SAID, NOT LEFT UNSAID (04.10, MTCoinShow): an owner who hid the coins tells -1 once.
    func about(to peer: String, askKey: Bool, now: Double) -> MTCoinAbout {
        let coinKey = MTCoinTx.cachedKeyTag
        if coinKey == nil { MTCoinTx.deriveForTheWord() }
        let keyDue = askKey || (coinKey.map { k in !MTCoinTx.toldKey(peer, k) } ?? false)
        let coins = MTCoinShow.on ? MTCoinBalance.now : -1
        let said = UserDefaults.standard.dictionary(forKey: "aboutCoins." + peer)
        let coinsDue = coins.map { c in (said?["c"] as? Int) != c && 600 <= now - ((said?["at"] as? Double) ?? 0) } ?? false
        return MTCoinAbout(keyDue: keyDue, coinsDue: coinsDue, coins: coins, key: coinKey, at: now)
    }
    func word(_ a: MTCoinAbout, to peer: String) -> [String: Any] {
        var word: [String: Any] = [:]
        if let coins = a.coins { word["c"] = coins }
        if let coinKey = a.key { word["k"] = coinKey }
        if let own = MTOwnWords.tag(for: peer) { word["o"] = own }   // a tag only my words make: a pair of my words knows itself (06.10)
        return word
    }
    func told(_ a: MTCoinAbout, to peer: String) {
        if let coins = a.coins { UserDefaults.standard.set(["c": coins, "at": a.at] as [String: Any], forKey: "aboutCoins." + peer) }
        if let coinKey = a.key { MTCoinTx.noteToldKey(peer, coinKey) }
    }
    @MainActor func heardAbout(_ o: [String: Any], from chat: String, at: Double) -> Bool {
        if let coins = o["c"] as? Int { MTCoinBoard.shared.note(chat, coins: coins, at: at) }   // the pair's balance (03.10)
        if let k = o["k"] as? String { MTCoinTx.notePeerFrom(chat, k) }   // the pair's coin key: v3 sends commit to it (COIN-TX-V3)
        if let own = o["o"] as? String { MTOwnWords.heard(own, from: chat) }   // the pair holds my words: no coin goes to it (06.10)
        // THEIR SEND FOUND NO KEY OF MINE (21.10.2026, «q»): the word they hold is lost or never came -- told again now
        if o["q"] != nil { MTCoinTx.forgetToldKey(chat); return true }
        return false
    }
    var balanceTail: String {
        guard MTCoinShow.on, let coins = MTCoinBalance.now else { return "" }
        return "C" + String(coins)
    }
    func heardBalance(_ coins: Int, from peer: String, at: Double) {
        Task { @MainActor in MTCoinBoard.shared.note(peer, coins: coins, at: at) }
    }
    func heardLevel(_ level: Int, from peer: String, at: Double) {
        Task { @MainActor in MTCoinBoard.shared.noteLevel(peer, level: level, at: at) }
    }
    func isLetter(_ text: String) -> Bool { MTCoinLetter.parse(text) != nil }
    func isLetter(_ m: Message) -> Bool { m.coinLetter != nil }
    func strays(_ text: String) -> Bool { text != MTCoinLetter.born && MTCoinLetter.parse(text) != nil }
    @MainActor func travels(_ m: Message) -> Bool { MTCoinSend.travels(m) }
    @MainActor func hold(_ m: Message, in chat: String) { MTCoinSend.hold(m, in: chat) }
    @MainActor func due(_ store: ChatStore) { MTCoinSend.due(store) }
    @MainActor func release(_ m: Message, in chat: String) { MTCoinSend.release(m, in: chat) }
    @MainActor func arrived(_ mid: String, from chat: String) { MTCoinSend.arrived(mid, from: chat) }
    @MainActor func settle(_ store: ChatStore) {
        MTCoinSend.settle(store)
        Task { @MainActor in await MTCoinTx.settle() }   // the transfers' records: the waiting ones decided, the pipes asked (MTCoinTx)
    }
    @MainActor func landed(_ row: Message, in chat: String, store: ChatStore) {
        guard !row.isFromMe else { return }
        // A COIN LETTER IS CREDITED ON ITS LANDING (the author's word 03.10 13:52), once, by its wire name (MTCoinLedger.receive)
        // -- a letter that names itself, never a copy (06.10).
        if !MTGroup.isKey(chat), let coin = row.coinLetter, !row.mid.isEmpty, MTCoinSend.credits(coin, mid: row.mid, from: chat) {
            MTCoinBook.ledger.receive(coin.c, from: chat, ref: row.mid, on: nil)
        }
        // A TRANSFER'S TELLING LETTER ASKS THE NODES (MTCoinTx): the letter credits nothing; the record it names is read from the log.
        if row.text.contains(MTCoinTx.link) {
            Task { @MainActor in await MTCoinTx.scan(why: "told") }
        }
        // A CHOSEN PERSON'S LETTER IS PAID BY ITSELF (MTAutoReact, the author's word 06.10.2026 14:3x UTC) -- a turn after its landing,
        // so the letter stands before the reaction that rides on it.
        if !MTGroup.isKey(chat), MTAutoReact.rule(chat) != nil {
            Task { @MainActor in MTAutoReact.landed(row, in: chat, store: store) }
        }
    }
    @MainActor func reacted(_ c: Int, ref: String, on sid: String, from chat: String) { MTCoinSend.reacted(c, ref: ref, on: sid, from: chat) }
    @MainActor func gifted(_ c: Int, from peer: String, ref: String, on target: String) {
        MTCoinBook.ledger.receive(c, from: peer, ref: ref, on: target)
    }
    @MainActor func heardSend(_ tx: String, on target: String) { MTCoinTx.heard(tx, on: target) }
    @MainActor func send(_ coins: Int, to conv: String, on target: String) async -> MTCoinSent {
        switch await MTCoinTx.send3(coins, conv: conv, on: target) {
        case .sent(let id): return .sent(id)
        case .pending: return .pending
        case .notApplicable(let why): return .refused(why)
        case .failed, .paced: return .failed
        }
    }
    @MainActor func canPay(_ chat: Chat, store: ChatStore) -> Bool { MTCoinSend.canPay(chat, store: store) }
    @MainActor func react(_ coins: Int, on m: Message, in chat: Chat, store: ChatStore) async -> Bool {
        await MTCoinSend.react(coins, on: m, in: chat, store: store)
    }
    @MainActor func mayRetry(_ m: Message) -> Bool { MTCoinSend.mayRetry(m) }
    func shelfLanded(_ text: String, mid: String, from conv: String, words: String, seat: String) async {
        guard let coin = MTCoinLetter.parse(text), coin.bound(to: mid),
              let e = MontanaSeedKeys.entropyFrom(mnemonic: words), e.count == 32 else { return }
        let move = MTCoinEntry(k: .receive, c: coin.c, ref: "mid:" + mid, peer: conv, on: nil, at: Date().timeIntervalSince1970)
        let laid = await MTCoinVault.lay([move], entropy: e)
        MontanaTrace.mark("shelf_coin", mid: mid, "seat=\(seat) coins=\(coin.c) rows=\(laid)")
    }
}

extension MTSeats {
    /// A PERSON ON THE SHELF'S OWN WORDS AND THE BALANCE OF THEIR BOOK AS THE SHELF HOLDS IT -- the phone's hands for the other end
    /// of a transfer to one's own account (MTCoinTx.landOwn, 12.10.2026). nil for the person seated, an unknown seat or a record
    /// that does not open. Read off the screen's thread.
    static func shelfCoins(_ id: String) -> (words: String, book: Int)? {
        guard let words = shelfWords(id) else { return nil }
        return (words, MTLocalCoinLedger.balance(of: shelf(folder: "AS:Montana/Coins", seat: id).appendingPathComponent(MTCoinPlace.book)))
    }
}

/// THE PEOPLE IN THE APP HEAR MY BALANCE MOVE (the author's words 04.10.2026 00:03 and 01:19 UTC: «the update instant, as by a web
/// socket»): a move of the book says the balance again to the correspondents in the app now, in the app word (E2E.coinBeacon) --
/// one round in two seconds however fast the coins come, so a minute of minting is thirty rounds to the people online, not one a coin.
@MainActor enum MTCoinTell {
    static let pace: UInt64 = 2
    private static var due: Task<Void, Never>?
    static func moved() {
        guard due == nil else { return }
        let wait = pace
        due = Task { @MainActor in
            try? await Task.sleep(nanoseconds: wait * 1_000_000_000)
            guard !Task.isCancelled else { return }
            due = nil
            tell()
        }
    }
    private static func tell() {
        guard let store = ChatStore.live else { return }
        for peer in store.appOnlineChats { E2E.shared.coinBeacon(to: peer) }
        MTTopNet.shared.put()   // the one table hears it in the same round
    }
}

/// THE PEOPLE'S COINS (the author's words 03.10.2026 19:23 and 19:25 UTC: «in the wallet, under the add-account button, the
/// top thirteen balances by coins, beautifully, with avatars and names, as in a social network»; «the coin's badge is the
/// number in the common rating»). Balances are public ([I-2]): every phone tells its pairs its own balance in its word about
/// itself (the key c beside the bio and the link), and this book keeps what each pair last told -- the newest word wins. The
/// rating is this phone's person among the people who told it: one owner of the people's balances on this phone.
@MainActor final class MTCoinBoard: ObservableObject {
    static let shared = MTCoinBoard()
    struct Told: Codable { var coins: Int; var at: Double }
    struct Place: Identifiable { let id: String; let coins: Int; let mine: Bool }
    @Published private(set) var told: [String: Told] = [:]
    nonisolated static let key = "coinBoard.told"
    /// THE PEOPLE'S LEVELS (the author's word 11.10.2026 18:2x UTC, MTLevelShow): the Global Level each pair last told in its
    /// presence words, the newest word wins, and a word that names none takes it away. The book is drawn again only when a level
    /// moves: the moment of every word is kept beside it unpublished, so the faces are not drawn again at every beat.
    struct Level: Codable { var level: Int; var at: Double }
    @Published private(set) var levels: [String: Level] = [:]
    private var levelHeardAt: [String: Double] = [:]
    nonisolated static let levelsKey = "coinBoard.levels"

    private init() {
        if let d = UserDefaults.standard.data(forKey: Self.key), let t = try? JSONDecoder().decode([String: Told].self, from: d) { told = t }
        levels = Self.readLevels()
    }
    /// The person lifted into the seat: the balances and the levels their own correspondents told them.
    func reread() {
        told = UserDefaults.standard.data(forKey: Self.key).flatMap { d in try? JSONDecoder().decode([String: Told].self, from: d) } ?? [:]
        levels = Self.readLevels()
        levelHeardAt = [:]
    }
    private static func readLevels() -> [String: Level] {
        UserDefaults.standard.data(forKey: levelsKey).flatMap { d in try? JSONDecoder().decode([String: Level].self, from: d) } ?? [:]
    }

    /// THE TOLD IS CAPPED BY THE CHAIN (18.10.2026, Agent 93, the critic's P-3; the author's word «close every point»): a pair's
    /// word says its balance and its level, and any build can say any number -- a third-party build says L13 and a billion coins, and
    /// every honest phone drew them by the face and in the rating. A told balance is kept now only up to what the pair's own coin
    /// chain proves on its node (proven and declared, by the key the pair named, MTCoinTx.peerFrom), and a told level up to the
    /// wallet member of that balance -- the Global Level is never above it (MTPersonChain.global). A pair whose chain is not read yet
    /// stands in no rating and wears no level; its chain is read at most once in ten minutes.
    private var chain: [String: (coins: Int, at: Double)] = [:]
    private var heardCoins: [String: Told] = [:]
    private var heardLevel: [String: Level] = [:]
    private var asking = Set<String>()
    private func proveChain(_ conv: String) {
        if let c = chain[conv], Date().timeIntervalSince1970 - c.at < 600 { return }
        guard !asking.contains(conv), let from = MTCoinTx.peerFrom(conv), let door = MTCoinTx.chainDoor(from) else { return }
        asking.insert(conv)
        Task { @MainActor in
            let st = await MTCoinTx.chain3(from, door: door)
            self.asking.remove(conv)
            guard let st else { return }
            self.chain[conv] = (Int(clamping: st.proven + st.declared), Date().timeIntervalSince1970)
            if let t = self.heardCoins[conv] { self.keepCoins(conv, t) }
            if let l = self.heardLevel[conv] { self.keepLevel(conv, l) }
        }
    }
    private func keepCoins(_ conv: String, _ t: Told) {
        guard let cap = chain[conv]?.coins else { return }
        // THE CHAIN'S NUMBER, NEVER THE TOLD ONE (P-4 of Agent 95, the author's word 19.10.2026 09:2x UTC «put it in»): the lower of the two
        // still let a build of one's own say 0 and draw every levelling's gift (MTCoinSendPage.levelPlan); the pair's word now only says
        // that it shows its coins, and the number is its chain's
        let coins = cap
        let moved = told[conv]?.coins != coins
        told[conv] = Told(coins: coins, at: t.at)
        guard moved else { return }
        if let d = try? JSONEncoder().encode(told) { UserDefaults.standard.set(d, forKey: Self.key) }
        MontanaTrace.markFolded("coin_board", "told=\(told.count)", window: 60)
    }
    private func keepLevel(_ conv: String, _ l: Level) {
        guard let cap = chain[conv]?.coins else { return }
        let level = min(l.level, MTFabricRules.walletLevel(cap))
        guard levels[conv]?.level != level else { return }
        levels[conv] = Level(level: level, at: l.at)
        if let d = try? JSONEncoder().encode(levels) { UserDefaults.standard.set(d, forKey: Self.levelsKey) }
        MontanaTrace.markFolded("level_board", "told=\(levels.count)", window: 60)
    }

    /// A pair's presence word told its Global Level, or named none (a negative level): kept when the word is newer than the last.
    func noteLevel(_ conv: String, level: Int, at: Double) {
        guard max(levels[conv]?.at ?? 0, levelHeardAt[conv] ?? 0) <= at else { return }
        levelHeardAt[conv] = at
        if 0 <= level {
            heardLevel[conv] = Level(level: level, at: at)
            proveChain(conv)
            keepLevel(conv, Level(level: level, at: at))
            return
        } else {
            heardLevel[conv] = nil
            guard levels.removeValue(forKey: conv) != nil else { return }
        }
        if let d = try? JSONEncoder().encode(levels) { UserDefaults.standard.set(d, forKey: Self.levelsKey) }
        MontanaTrace.markFolded("level_board", "told=\(levels.count)", window: 60)
    }

    /// A pair's word about itself carried its balance: kept when it is newer than the one held.
    func note(_ conv: String, coins: Int, at: Double) {
        guard (told[conv]?.at ?? 0) <= at else { return }
        // A NEGATIVE BALANCE IS «HIDDEN» (04.10, MTCoinShow): the pair turned its coins off, and its row leaves this rating.
        guard 0 <= coins else {
            heardCoins[conv] = nil
            guard told.removeValue(forKey: conv) != nil else { return }
            if let d = try? JSONEncoder().encode(told) { UserDefaults.standard.set(d, forKey: Self.key) }
            MontanaTrace.markFolded("coin_board", "hidden told=\(told.count)", window: 60)
            return
        }
        // Every presence word tells the balance now (E2E.coinTail): kept up to what the pair's chain proves (keepCoins).
        heardCoins[conv] = Told(coins: coins, at: at)
        proveChain(conv)
        keepCoins(conv, Told(coins: coins, at: at))
    }

    /// A pair holding my words told my own coins, not a person's beside me (MTOwnWords): it stands in no rating.
    private var others: [String: Told] { told.filter { !MTOwnWords.mine($0.key) } }
    /// The rating: this phone's person and every pair that told its balance, the most coins first; a tie keeps me first.
    func rating(mine: Int) -> [Place] {
        (others.map { Place(id: $0.key, coins: $0.value.coins, mine: false) } + [Place(id: "", coins: mine, mine: true)])
            .sorted { $0.coins != $1.coins ? $1.coins < $0.coins : $0.mine }
    }

    /// My place in the rating: one more than the people who told more coins than I hold.
    func rank(mine: Int) -> Int { 1 + others.values.filter { mine < $0.coins }.count }
}

/// THE MONEY FLOW IS A CHAT'S OWN (the author's word 04.10.2026 09:23 UTC: «if my chat is turned with one correspondent, it concerns
/// only the chat with them, not all -- part the states»). Each conversation keeps its own turn of the feed and its live words both
/// ways. Read from any thread; the screens observe the change.
@MainActor final class MTMoneyFlow: ObservableObject {
    static let shared = MTMoneyFlow()
    /// THE FLOW MINTS NOTHING (the author's word 11871, 29.10.2026: «only the rule of the constitution, 1 coin is 1 second, by the
    /// core»; decision 375 «a»): from 22.10.2026 21:00 UTC only the chain mints, and since build 2320 no bubble of a flow's chat
    /// asks the book; the coins its bubbles earned before stand in the book as history (MTChatMint). A call moves no coin (the
    /// author's word 29.10.2026).
    @Published private(set) var turns = 0
    nonisolated static func isOn(_ conv: String) -> Bool { !conv.isEmpty && UserDefaults.standard.bool(forKey: "moneyFlow." + conv) }   // a conversation's own key (SeedScope.dataPrefixes)
    func on(_ conv: String) -> Bool { Self.isOn(conv) }
    func set(_ conv: String, _ on: Bool) {
        UserDefaults.standard.set(on, forKey: "moneyFlow." + conv)
        turns += 1
    }
}

/// The balance badge and disclosure are on by default (14.10.2026). An explicit
/// privacy choice stays in force. Opening the wallet explains the public ranking.
enum MTCoinShow {
    static let key = "coins.shown"   // NOT-UI: the owner's balance privacy preference
    static let toldKey = "top.told"  // NOT-UI: the wallet explained the public ranking
    static var on: Bool { UserDefaults.standard.object(forKey: key) as? Bool ?? true }
}

/// THE MONTANA TOP (the author's words 04.10.2026 00:03, 02:40 and 02:47 UTC: «a live set as by a web socket, the update instant from
/// the nodes»; «everyone has one source of all data»; «who does not show is not in the top»). One public table of the game's coins,
/// the same on every node (/top-put, /top-get): this phone puts its own row and the table comes back whole. A row is named by sha256
/// of a token only the words derive -- HKDF of the entropy under one label, then one HMAC, as the shelf of one's own node
/// (MontanaHomeNode) -- so only its owner rewrites or withdraws it; a row stands at its owner's balance at once, the fact (05.10).
/// The game's coins are not Montana: the protocol's money stays unseen ([I-2]); the table holds what its owners chose to show.
@MainActor final class MTTopNet: ObservableObject {
    static let shared = MTTopNet()
    struct Row: Identifiable, Equatable { let id: String; let name: String; let coins: Int }
    /// The rows the nodes answered, the most coins first; empty until a node that keeps the table speaks.
    @Published private(set) var rows: [Row] = []
    /// A node answered: before the nodes keep the table the wallet shows the pairs' rating (MTCoinBoard).
    @Published private(set) var answered = false
    /// This person's place in the whole table, or nil when they are not in it.
    @Published private(set) var rank: Int?
    private static let keyLabel = Data("mt-top-owner-v1".utf8)   // NOT-UI: the derivation's own label
    private static let tokenLabel = Data("mt-top-token".utf8)    // NOT-UI: the token's own label
    private var asking = false

    static func key(entropy: Data) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: entropy), salt: Data(), info: keyLabel, outputByteCount: 32)
    }
    static func token(_ k: SymmetricKey) -> Data { Data(HMAC<SHA256>.authenticationCode(for: tokenLabel, using: k)) }
    static func row(token t: Data) -> String { MontanaHomeNode.hex(Data(SHA256.hash(data: t))) }
    private static func myToken() -> Data? {
        guard let m = MontanaSeed.mnemonic, let e = MontanaSeedKeys.entropyFrom(mnemonic: m), e.count == 32 else { return nil }
        return token(key(entropy: e))
    }
    /// The row this seed owns, or nil without a seed.
    static func myRow() -> String? { myToken().map { row(token: $0) } }
    /// THE FROZEN VECTORS (computed outside this code: RFC 5869 HKDF-SHA-256, HMAC-SHA-256 and SHA-256 on the counting bytes
    /// 0x00..0x1f; tools/mt-top-check.py computes them again on every build): the home node's label in place of this one, a
    /// reversed root or a row hashed as hex text all fail them.
    static func keyKAT() -> Bool {
        let counting = Data((0..<32).map { UInt8($0) })
        let k = key(entropy: counting)
        let t = token(k)
        return MontanaHomeNode.hex(k.withUnsafeBytes { Data($0) }) == "7a504b1911419189651d037cfa3776404731270ebe01a2cbefe7aabbca5140d5"
            && MontanaHomeNode.hex(t) == "67b2f9e4f8ba74bffee41cdfd8de2d3efca20554a495910ebc823b8ef4545ce2"
            && row(token: t) == "f0b3cb47ae97a4849fd8d42d75bbbcc395f93b9b4adae16c5bb0e91b4641d369"
    }

    /// The row says the coins now -- paced by MTCoinTell, never before the wallet told its owner what showing does, never when
    /// the owner hid the coins.
    func put() {
        guard MTCoinShow.on else { withdrawUnasked(); return }
        guard UserDefaults.standard.bool(forKey: MTCoinShow.toldKey), let t = Self.myToken(), let coins = MTCoinBalance.now else { return }
        // THE ROW TELLS THE SEED'S UNION, NEVER ONE DEVICE'S SHARE (the author's word 04.10.2026 12:51 UTC: «check the sync over the
        // network as a pendulum»): a device of the seed that has not gathered the others' moves in half a minute would pull the seed's
        // row down to its own share and the next device would lift it again; it gathers first, and the gathering puts the row.
        guard MTCoinVault.shared.fresh else { MTCoinVault.shared.soon("put", after: 1); return }
        let body: [String: Any] = ["token": MontanaHomeNode.hex(t), "name": String(E2E.myDisplayName().prefix(64)), "coins": coins]
        Task {
            // THE ROW PROVES ITS COIN KEY (P-4 of Agent 95, the author's word 19.10.2026 09:2x UTC «put it in»): the node shows that key's
            // chain as it folds it, never the number told here -- a build of one's own once stood first by saying a billion
            let proof = await Task.detached(priority: .utility) { Self.keyProof(t) }.value
            var b = body
            for (k, v) in proof ?? [:] { b[k] = v }
            await self.send(b, why: "put")
        }
    }
    /// The seed's coin key signs ASCII mt-top-key-v1 and the row's token: the node verifies it with the core and reads that key's chain.
    nonisolated static func keyProof(_ token: Data) -> [String: String]? {
        guard let k = MTCoinTx.keys(), let sig = MontanaPQ.sign(seckey: k.sk, message: Data("mt-top-key-v1".utf8) + token) else { return nil }
        return ["pk": k.pk.base64EncodedString(), "sig": sig.base64EncodedString()]
    }
    /// A ROW PUT BEFORE THE YES WAS ASKED LEAVES (5.1.2(i), 08.10.2026): earlier builds showed a person in the table by default; a
    /// person who never turned the switch has their row withdrawn from every node once, as soon as their words can name it.
    static let unaskedKey = "top.unaskedWithdrawn"   // NOT-UI: this device withdrew the row of a person never asked
    /// WHAT THIS BUILD FOUND AT ITS FIRST LAUNCH (the critic 08.10): whether an earlier build of this device had already published
    /// the row (its wallet had told what showing does). Read once, before any wallet of this build opens -- the wallet sets the
    /// told mark at every opening, and a device that never published must not take away a row a yes put on another device.
    nonisolated static let toldBeforeKey = "top.toldBeforeConsent"   // NOT-UI: the told mark as this build first found it
    static func noteFirstLaunch() {
        let d = UserDefaults.standard
        if d.object(forKey: toldBeforeKey) == nil { d.set(d.bool(forKey: MTCoinShow.toldKey), forKey: toldBeforeKey) }
    }
    private func withdrawUnasked() {
        let d = UserDefaults.standard
        guard d.object(forKey: MTCoinShow.key) == nil, d.bool(forKey: Self.toldBeforeKey), !d.bool(forKey: Self.unaskedKey),
              Self.myToken() != nil else { return }
        d.set(true, forKey: Self.unaskedKey)
        withdraw()
    }
    /// The owner hid the coins: the row leaves the table on every node, and leaves this screen at once.
    func withdraw() {
        guard let t = Self.myToken() else { return }
        let mine = Self.row(token: t)
        rows.removeAll { $0.id == mine }
        rank = nil
        Task { await self.send(["token": MontanaHomeNode.hex(t), "hide": true], why: "hide", everyDoor: true) }
    }
    /// The owner's switch moved: the table and the correspondents hear it now, not at the next coin.
    func showChanged(_ on: Bool) {
        if on { put() } else { withdraw() }
        if let store = ChatStore.live {
            for c in store.listChats() where !c.isGroup { if let conv = c.convId { E2E.shared.tellBalance(to: conv) } }
        }
        MontanaTrace.mark("coins_shown", on ? "on" : "off")
    }
    /// A withdrawal knocks every node itself (everyDoor): a row hidden on one node and forwarded nowhere would stand on the other.
    private func send(_ body: [String: Any], why: String, everyDoor: Bool = false) async {
        guard let d = try? JSONSerialization.data(withJSONObject: body) else { return }
        var heard = 0
        for b in MontanaWakePush.orderedBases(for: "top") {
            guard let u = URL(string: b + "/top-put") else { continue }   // SERVER-DEBT-ACK: the accelerator node (rung 4), the public table
            var req = URLRequest(url: u); req.httpMethod = "POST"; req.timeoutInterval = 8   // SERVER-DEBT-ACK: the accelerator node (rung 4)
            req.setValue("application/json", forHTTPHeaderField: "content-type")
            req.httpBody = d
            if let r = try? await URLSession.shared.data(for: req), (r.1 as? HTTPURLResponse)?.statusCode == 200 {   // SERVER-DEBT-ACK: the accelerator node (rung 4)
                heard += 1
                if !everyDoor { break }
            }
        }
        MontanaTrace.markFolded("top_put", "why=\(why) doors=\(heard)", window: 60)
    }
    /// The whole table and this person's place in it, asked of the first node that keeps it.
    func read() async {
        guard !asking else { return }
        asking = true
        defer { asking = false }
        var body: [String: Any] = [:]
        if let me = Self.myRow() { body["row"] = me }
        guard let d = try? JSONSerialization.data(withJSONObject: body) else { return }
        for b in MontanaWakePush.orderedBases(for: "top") {
            guard let u = URL(string: b + "/top-get") else { continue }   // SERVER-DEBT-ACK: the accelerator node (rung 4), the public table
            var req = URLRequest(url: u); req.httpMethod = "POST"; req.timeoutInterval = 6   // SERVER-DEBT-ACK: the accelerator node (rung 4)
            req.setValue("application/json", forHTTPHeaderField: "content-type")
            req.httpBody = d
            guard let r = try? await URLSession.shared.data(for: req), (r.1 as? HTTPURLResponse)?.statusCode == 200,   // SERVER-DEBT-ACK: the accelerator node (rung 4)
                  let o = try? JSONSerialization.jsonObject(with: r.0) as? [String: Any],
                  let list = o["rows"] as? [[String: Any]] else { continue }
            rows = list.compactMap { x in
                guard let id = x["row"] as? String, let coins = x["coins"] as? Int else { return nil }
                // A NAME IS SHOWN AS LETTERS ONLY (the critic, 04.10): the node strips the controls and the direction marks, and the
                // phone does again -- a node of another hand owes this screen nothing.
                let name = String(String.UnicodeScalarView(((x["name"] as? String) ?? "").unicodeScalars.filter { u in
                    u.properties.generalCategory != .control && u.properties.generalCategory != .format
                }))
                return Row(id: id, name: name, coins: coins)
            }
            rank = o["rank"] as? Int
            if !answered { MontanaTrace.mark("top_get", "rows=\(rows.count) rank=\(rank ?? 0)") }
            answered = true
            return
        }
    }
}

/// THE BOOK RIDES THE SEED (the author's words 04.10.2026 10:36-10:42 UTC: «I must log in by my seed on another device and my
/// balance must surely be kept -- the critical part»; the choice 10:40: «the book by the seed on the nodes»; «build by constitution 6
/// fully» -- the phone is a full node). Every move of the book is sealed under a key only the words derive (ChaCha20-Poly1305, the
/// vault's own cipher [I-1]) and laid on every node in pieces; any device with the same words gathers the union of all of them -- a
/// move is its name, so the union is the book, the same on every device of the seed. What a node holds is the node's own word: it
/// answers with the names of the pieces it keeps, and each node is sent the moves its pieces lack, never more. Past `fold` pieces on
/// a node the whole book is laid there anew and the old pieces go in the same breath. The top waits for the first answer (heard):
/// a device that has not gathered its seed's book never tells the table a balance it does not hold.
@MainActor final class MTCoinVault: ObservableObject {
    static let shared = MTCoinVault()
    nonisolated private static let tokenLabel = Data("mt-coins-vault-token".utf8)      // NOT-UI: the token's own label
    nonisolated private static let aad = Data("mt.coins.vault".utf8)                   // NOT-UI: the words the seal is bound to
    nonisolated private static let tipLabel = Data("mt-timechain-tip-token".utf8)      // NOT-UI: the tips' row label (MTTimeChainTip)
    nonisolated private static let ownLabel = Data("mt-own-words-v1".utf8)             // NOT-UI: the own-words tag's label (MTOwnWords)
    nonisolated private static let nodeLabel = Data("mt-coins-vault-node-v1".utf8)     // NOT-UI: a node's own row label (nodeToken)
    /// How many pieces a node keeps for a seed before the whole book is laid there as one (about three hours of minting, a piece a
    /// minute); a piece carries `span` moves at most.
    static let fold = 192
    static let span = 8000
    /// A node answered this seed's book since the launch or the seat's move.
    @Published private(set) var heard = false
    private var heardAt: Double = 0
    /// The seed's union was gathered within the minting's minute: what this device tells the top is the seed's, not its own share.
    /// ONE CLOCK FOR THE GATHER (18.10.2026, Agent 89, T1 2238): the moves of a minute ride one piece (soon, after 60), and a half-minute
    /// freshness asked by the top's two-second round gathered twice a minute -- 287 of 372 gathers within 30 s of the one before, a
    /// piece per row each time, the fold to the whole book twice as often as its own count says. The top waits for the same minute.
    static let freshS: Double = 60
    var fresh: Bool { heard && Date().timeIntervalSince1970 - heardAt < Self.freshS }
    private var pieces: [String: Set<String>] = [:]   // a piece's name -> the names of the moves it carries, opened once
    private var held: [String: [String]] = [:]         // a node's door -> the pieces it said it keeps
    private var full = Set<String>()                   // the doors that refused a piece as full: laid whole next
    private var running = false, again = false
    private var dueAt = Double.infinity
    /// THE PIECES OPENED STAND ACROSS LAUNCHES (OZ 1, build 2342; T1 2340 cold launch 19:30 UTC: coins_vault why=read rows=4/4
    /// got=120756 joined=0 -- every launch fetched, opened and decoded the whole book from all four rows, because «have» named only the
    /// pieces this process had opened and a process is born with none). The names of the moves each piece carries, and the pieces each
    /// row said it keeps, are kept in the seed's own file (coin-vault-pieces): read once at the first gather, written when a gather
    /// changed them and not oftener than every ten minutes, forgotten with the seat. A piece is its own name (SHA-256 of its blob), so a
    /// kept piece is never stale; one the node no longer holds leaves at the gather, as before; a file of another token lays nothing.
    private struct KeptPieces: Codable { var token: String; var pieces: [String: [String]]; var held: [String: [String]] }
    nonisolated private static let keptFile = "coin-vault-pieces"   // NOT-UI: the file's own name
    private var keptRead = false
    private var keptWroteAt: Double = 0
    private let disk = DispatchQueue(label: "montana.coin-vault", qos: .utility)
    private func readKept(token: String) async {
        guard !keptRead else { return }
        keptRead = true
        guard let u = MTCoinPlace.file(Self.keptFile) else { return }
        let read = await Task.detached(priority: .utility) { () -> KeptPieces? in
            guard let d = try? Data(contentsOf: u) else { return nil }
            return try? JSONDecoder().decode(KeptPieces.self, from: d)
        }.value
        guard let read, read.token == token, pieces.isEmpty else { return }
        pieces = read.pieces.mapValues { Set($0) }
        held = read.held
        MontanaTrace.mark("coins_vault", "kept pieces=\(pieces.count) rows=\(held.count)")
    }
    private func writeKept(token: String) {
        let now = Date().timeIntervalSince1970
        guard 600 < now - keptWroteAt, let u = MTCoinPlace.file(Self.keptFile) else { return }
        keptWroteAt = now
        let k = KeptPieces(token: token, pieces: pieces.mapValues { Array($0) }, held: held)
        disk.async {
            guard let d = try? JSONEncoder().encode(k) else { return }
            MTDiskDoor.write(d, to: u, Self.keptFile, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
    }

    nonisolated static func keys(entropy: Data) -> (seal: SymmetricKey, token: Data, tip: Data) {
        let seal = MTSeedVault.seal(entropy), owner = MTSeedVault.owner(entropy)   // the seed's vault keys, shared (MTSeedVault)
        return (seal, Data(HMAC<SHA256>.authenticationCode(for: tokenLabel, using: owner)),
                Data(HMAC<SHA256>.authenticationCode(for: tipLabel, using: owner)))
    }
    /// THE TAG OF A PAIR ONLY THE SAME WORDS MAKE (MTOwnWords): HMAC-SHA-256 under the owner key over the label and the conversation's
    /// name. A pair of other words reads 32 bytes it can neither check nor tie to any other conversation; no node sees them (the word
    /// about oneself rides end to end).
    nonisolated static func ownTag(entropy: Data, conv: String) -> Data {
        Data(HMAC<SHA256>.authenticationCode(for: ownLabel + Data(conv.utf8), using: ownerKey(entropy)))
    }
    nonisolated static func ownTagHolds(_ tag: Data, entropy: Data, conv: String) -> Bool {
        HMAC<SHA256>.isValidAuthenticationCode(tag, authenticating: ownLabel + Data(conv.utf8), using: ownerKey(entropy))
    }
    /// EVERY NODE HOLDS THE BOOK UNDER A ROW OF ITS OWN (the author's words 06.10.2026 09:3x-09:4x UTC: «close the double spends»; «the safety of the restore by the seed»): the one
    /// token the seed sent to every node named the same row on all of them, and a put deletes the pieces it names -- one node that
    /// read the token from a request could empty the book on every other node, and the words restored nothing. A node's row is
    /// HMAC-SHA-256 under the owner key over this label and the node's host: a node learns its own row and no other. The common row
    /// stays beside it, read and laid, while builds before this one read nothing else.
    nonisolated static func nodeToken(entropy: Data, host: String) -> Data {
        Data(HMAC<SHA256>.authenticationCode(for: nodeLabel + Data(host.utf8), using: ownerKey(entropy)))
    }
    /// Every node's two rows: its own first, then the common one.
    private static func rows(_ doors: [String], common: String, entropy: Data) -> [(slot: String, door: String, token: String)] {
        doors.flatMap { door in
            [(slot: door + "#own", door: door, token: MontanaHomeNode.hex(nodeToken(entropy: entropy, host: URL(string: door)?.host ?? door))),
             (slot: door, door: door, token: common)]
        }
    }
    nonisolated private static func ownerKey(_ entropy: Data) -> SymmetricKey {
        MTSeedVault.owner(entropy)
    }
    fileprivate static func mine() -> (seal: SymmetricKey, token: Data, tip: Data)? {
        guard let m = MontanaSeed.mnemonic, let e = MontanaSeedKeys.entropyFrom(mnemonic: m), e.count == 32 else { return nil }
        return keys(entropy: e)
    }
    /// THE FROZEN VECTORS (computed outside this code: RFC 5869 HKDF-SHA-256, HMAC-SHA-256 and SHA-256 on the counting bytes
    /// 0x00..0x1f; tools/mt-top-check.py computes them again on every build): the top's labels in place of these, a reversed
    /// root or a row hashed as hex text all fail them.
    static func keyKAT() -> Bool {
        let k = keys(entropy: Data((0..<32).map { UInt8($0) }))
        return MontanaHomeNode.hex(k.seal.withUnsafeBytes { Data($0) }) == "e9720340e7dcb4b6c2befea9a657718560646f727614f732971bf9ea7d3795fb"
            && MontanaHomeNode.hex(k.token) == "4b7fc64e903945bee08b4fc45f7ca094d9b61ae2c96f4d97ebd1ccd8b4b9ab86"
            && MontanaHomeNode.hex(Data(SHA256.hash(data: k.token))) == "9e34605e5200c5f339f4a527f0654af5436a96b629f66835f91495b65e0ba245"
    }
    nonisolated static func seal(_ moves: [MTCoinEntry], with key: SymmetricKey) -> Data? {
        guard let plain = try? JSONEncoder().encode(moves), let packed = try? (plain as NSData).compressed(using: .lzfse) as Data else { return nil }
        return try? ChaChaPoly.seal(packed, using: key, authenticating: aad).combined
    }
    nonisolated static func open(_ sealed: Data, with key: SymmetricKey) -> [MTCoinEntry]? {
        guard let box = try? ChaChaPoly.SealedBox(combined: sealed), let packed = try? ChaChaPoly.open(box, using: key, authenticating: aad),
              let plain = try? (packed as NSData).decompressed(using: .lzfse) as Data else { return nil }
        return try? JSONDecoder().decode([MTCoinEntry].self, from: plain)
    }
    /// The person who left the seat takes their vault's memory with them.
    func forget() {
        heard = false; heardAt = 0; pieces = [:]; held = [:]; full = []
        keptRead = false; keptWroteAt = 0
        if let u = MTCoinPlace.file(Self.keptFile) { disk.async { try? FileManager.default.removeItem(at: u) } }   // the kept pieces go with the person
    }
    /// A gathering soon: the moves of a minute -- the minting's own window -- ride one piece, never one each; the nearest ask wins, so
    /// a row waiting for the seed's union never waits behind a minute's.
    func soon(_ why: String, after seconds: Double = 60) {
        let at = Date().timeIntervalSince1970 + seconds
        guard at < dueAt else { return }
        dueAt = at
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            guard let self, self.dueAt == at else { return }
            self.dueAt = .infinity
            Task { await self.gather(why: why) }
        }
    }
    /// The seat moved while the gather waited (MTCoinBook.generation): nothing of the person who left is written or kept.
    private func moved(_ gen: Int, _ why: String) -> Bool {
        guard gen != MTCoinBook.generation else { return false }
        MontanaTrace.mark("coins_vault", "why=\(why) the seat moved -- the gather writes nothing")
        return true
    }
    func gather(why: String) async {
        if running { again = true; return }
        guard let k = Self.mine(), let words = MontanaSeed.mnemonic, let e = MontanaSeedKeys.entropyFrom(mnemonic: words), e.count == 32 else { return }
        let gen = MTCoinBook.generation
        let doors = MontanaWakePush.oneDoorPerNode(MontanaWakePush.orderedBases(for: "vault"))
        guard !doors.isEmpty else { return }
        running = true
        defer { running = false; if again { again = false; soon("again", after: 1) } }
        let token = MontanaHomeNode.hex(k.token)
        await readKept(token: token)
        if moved(gen, why) { return }
        let heldBefore = held, piecesBefore = Set(pieces.keys)
        let rows = Self.rows(doors, common: token, entropy: e)
        var answered: [String] = []
        var fresh: [MTCoinEntry] = []
        for r in rows {
            let door = r.door
            // THE ROW IS ASKED FOR WHAT IT LACKS HERE, NOT FOR AN ARBITRARY 256 OF EVERY ROW'S PIECES (18.10.2026, Agent 89, T1 2238): four
            // rows hold one book under four piece names, the pieces this process opened ran past the node's 256, and the prefix of a
            // dictionary named a different part each time -- 296 of 372 gathers in 11 h took the whole book again (12.3 M moves fetched,
            // opened and decoded, a gather every half minute while minting). A row's own pieces, opened here, are what it need not send.
            let have = Array((held[r.slot] ?? []).filter { pieces[$0] != nil }.prefix(256))
            guard case let (200, o?) = await MTSeedVault.post(door + "/vault-get", ["token": r.token, "have": have], timeout: 20),
                  let ids = o["held"] as? [String] else { continue }
            if moved(gen, why) { return }
            for x in (o["pieces"] as? [[String: Any]]) ?? [] {
                guard let id = x["piece"] as? String, let b = (x["blob"] as? String).flatMap({ Data(base64Encoded: $0) }),
                      MontanaHomeNode.hex(Data(SHA256.hash(data: b))) == id else { continue }   // a piece is its own name
                let key = k.seal
                guard let moves = await Task.detached(priority: .utility, operation: { MTCoinVault.open(b, with: key) }).value else { continue }
                if moved(gen, why) { return }
                pieces[id] = Set(moves.map(\.id))
                fresh += moves
            }
            held[r.slot] = ids
            answered.append(r.slot)
        }
        guard !answered.isEmpty, !moved(gen, why) else { return }
        heard = true
        heardAt = Date().timeIntervalSince1970
        let ledger = MTLocalCoinLedger.shared.whole
        let joined = ledger.join(fresh)
        let book = ledger.entries
        // WHAT EACH ROW LACKS IS RECKONED OFF THE MAIN THREAD (the author's words 23.10.2026 15:0x UTC: «on T1, build 2296, the chats
        // page stutters when I enter and use it -- check it and make it clean, without stalls»). Measured on T1 that minute: this
        // reckoning -- the union of every piece's moves and the book filtered by it, 30 089 moves for each of four rows -- held the
        // main thread 84 ms at a chat's opening, 101 ms in the chats list and 72 ms at the drawer (frame_stack, MTCoinVault.gather
        // at MTWalletCore.swift:1199-1205 by the dSYM of 2296), at every return to the screen and after every spend. The same
        // answer, reckoned on a copy; only the laying, which awaits the nodes anyway, comes back here.
        let plans = await Task.detached(priority: .userInitiated) { [answered, book, pieces, held, full, fold = Self.fold] in
            MTCoinVault.plan(answered, book: book, pieces: pieces, held: held, full: full, fold: fold)
        }.value
        if moved(gen, why) { return }
        var laid = 0, whole = 0
        for plan in plans {
            let slot = plan.slot, lacking = plan.lacking, anew = plan.anew
            guard let r = rows.first(where: { x in x.slot == slot }) else { continue }
            var replace = plan.replace
            for start in stride(from: 0, to: lacking.count, by: Self.span) {
                let part = Array(lacking[start..<min(start + Self.span, lacking.count)])
                // THE OLD PIECES GO WITH THE LAST NEW ONE (the coin audit's sixth point, 05.10.2026 18:4x UTC): the first part
                // carried the replace, so a refusal or an ended process after it left the node a part of the book, and «full»
                // repeated that same part. Every part is laid first; the last one takes the old pieces away.
                let last = lacking.count <= start + Self.span
                let key = k.seal
                guard let sealed = await Task.detached(priority: .utility, operation: { MTCoinVault.seal(part, with: key) }).value else { break }
                if moved(gen, why) { return }
                let (code, o) = await MTSeedVault.post(r.door + "/vault-put", ["token": r.token, "blob": sealed.base64EncodedString(), "replace": last ? replace : []], timeout: 30)
                if moved(gen, why) { return }   // the old seed's own book went to its own row; nothing more is kept here
                if code == 413 { full.insert(slot); break }
                guard code == 200, let id = o?["piece"] as? String else { break }
                pieces[id] = Set(part.map(\.id))
                let gone = last ? replace : []
                held[slot] = (held[slot] ?? []).filter { !gone.contains($0) } + [id]
                if last { replace = [] }
                laid += part.count
                if anew { whole += 1 }
            }
            if anew, whole > 0 { full.remove(slot) }
        }
        let live = Set(held.values.flatMap { $0 })
        pieces = pieces.filter { live.contains($0.key) }   // a piece no node keeps is forgotten here too
        if held != heldBefore || Set(pieces.keys) != piecesBefore { writeKept(token: token) }
        MontanaTrace.mark("coins_vault", "why=\(why) rows=\(answered.count)/\(rows.count) got=\(fresh.count) joined=\(joined) laid=\(laid) whole=\(whole) moves=\(book.count)")
        MTTopNet.shared.put()   // the row tells the union just gathered
    }
    private struct Plan { let slot: String; let lacking: [MTCoinEntry]; let replace: [String]; let anew: Bool }
    private nonisolated static func plan(_ answered: [String], book: [MTCoinEntry], pieces: [String: Set<String>],
                                         held: [String: [String]], full: Set<String>, fold: Int) -> [Plan] {
        var inBook: Set<String>?
        var plans: [Plan] = []
        for slot in answered {
            let ids = held[slot] ?? []
            var carried = Set<String>()
            for id in ids { carried.formUnion(pieces[id] ?? []) }
            let anew = fold <= ids.count || full.contains(slot)
            let lacking = anew ? book : book.filter { !carried.contains($0.id) }
            guard !lacking.isEmpty else { continue }
            // ONLY A PIECE READ HERE IS REPLACED (the coin audit's third point, 05.10.2026 18:4x UTC): a piece that would not open
            // -- a book of a later build, a broken blob -- or whose moves the book did not take was skipped above but stood in the
            // replace list, and its moves left every node. It stays on the node now, beside the whole.
            var replace: [String] = []
            if anew {
                let whole = inBook ?? Set(book.map(\.id))
                inBook = whole
                replace = ids.filter { id in pieces[id].map { moves in moves.isSubset(of: whole) } ?? false }
            }
            plans.append(Plan(slot: slot, lacking: lacking, replace: replace, anew: anew))
        }
        return plans
    }

    /// A PERSON ON THE SHELF IS CREDITED IN THEIR OWN BOOK (07.10, MTShelfPost): the moves are sealed under the key only their
    /// words derive and laid on every node under both their rows -- the node's own and the common one -- exactly as their own
    /// gather lays them; their gather at the lift, or any device of their words, takes the union. The rows that took the piece.
    static func lay(_ moves: [MTCoinEntry], entropy: Data) async -> Int {
        guard entropy.count == 32, !moves.isEmpty else { return 0 }
        let k = keys(entropy: entropy)
        let doors = MontanaWakePush.oneDoorPerNode(MontanaWakePush.orderedBases(for: "vault"))
        guard !doors.isEmpty, let sealed = seal(moves, with: k.seal) else { return 0 }
        var took = 0
        for r in rows(doors, common: MontanaHomeNode.hex(k.token), entropy: entropy) {
            let (code, _) = await MTSeedVault.post(r.door + "/vault-put", ["token": r.token, "blob": sealed.base64EncodedString(), "replace": [String]()], timeout: 30)
            if code == 200 { took += 1 }
        }
        return took
    }
}

/// THE TIMECHAIN'S TIP RIDES ONE ROUND TRIP (the author's words 04.10.2026 13:30-13:34 UTC: «find the lightest record of the
/// TimeChain, so the sync tends to the speed of a ping -- a special file and only the last 13 records; by the constitution, points 0 4 5
/// 6 8 10»; «right, fix it and build it in 2105»). Every device of the words writes its own lane -- one writer, so two phones never
/// contend for one link -- and every link carries, beside its move, the lane's running balance: the last link says the lane's coins.
/// The tip is the lane's last thirteen links in their own bytes, sealed under the words' key: one piece of each device on every node,
/// beside the book (MTCoinVault) in a row of its own, replaced as the lane grows. A device reads the others' tips in one round trip:
/// pieces it opened before ride nothing back; a lane behind by thirteen links or less gives its missing moves in the same piece,
/// joined by their names; a longer gap or a seal that breaks the chain asks the book. The head also says the writer's balance of the
/// whole book once it had gathered it, so a device restored by its words shows the seed's coins before the book lands. The number
/// shown stays the book's, where a move counts once by its name: a coin of a letter is born on every device of the words the letter
/// reaches, and lanes summed would count it twice.
@MainActor final class MTTimeChainTip: ObservableObject {
    static let shared = MTTimeChainTip()
    nonisolated static let depth = 13
    static let file = "timechain-tip.bin"   // NOT-UI: the tip's file name
    nonisolated static let aad = Data("mt.timechain.tip".utf8)   // NOT-UI: the words the tip's seal is bound to
    nonisolated static let kinds: [MTCoinEntry.Kind] = [.earn, .receive, .spend, .send, .burn]
    struct Link: Equatable {
        var n: UInt32, at: Int64, k: UInt8, c: UInt64, b: Int64
        var ref: String, peer: String, on: String
        var signed: Int64 { k < 2 ? Int64(c) : -Int64(c) }
    }
    struct Tip {
        var lane = Data(), seen: Int64 = 0, heard = false, prev = Data(count: 32), links: [Link] = []
    }
    /// The balance of the whole book the freshest tip of another device told, written after that device had gathered the book.
    @Published private(set) var seen: Int?
    private var tip: Tip?
    private var heads: [Data: (n: UInt32, hash: Data)] = [:]   // another device's lane: the last link of it this device took
    private var seenAt: Int64 = 0
    private var opened: [String: Data] = [:]   // a piece's name: its lane, opened once
    private var mine: [String: String] = [:]   // a node's door: the piece of this lane it holds now
    private var stale = Set<String>()          // pieces of this lane from before, gone at the next put
    private var putDue = false, putting = false, again = false, getting = false, checked = false
    private var putAt: Double = 0
    private let disk = DispatchQueue(label: "montana.timechain-tip", qos: .utility)

    /// The person lifted into the seat: the lane of the person who left goes with them; the seated person's is read at the next ask.
    func reread() { tip = nil; heads = [:]; seen = nil; seenAt = 0; opened = [:]; mine = [:]; stale = [] }

    /// This device's lane, read once from its file; born at the first ask where none stands. A file that stands and would not
    /// open is never written over: the lane waits for the next ask.
    private func lane() -> Tip? {
        if let tip { return tip }
        guard let u = MTCoinPlace.file(Self.file) else { return nil }
        if let d = try? Data(contentsOf: u) {
            guard let read = Self.decode(d), read.lane.count == 16 else { return nil }
            tip = read
        } else if !FileManager.default.fileExists(atPath: u.path) {
            tip = Tip(lane: Data((0..<16).map { _ in UInt8.random(in: 0...255) }))
        }
        return tip
    }

    /// This device's own moves (MTLocalCoinLedger.keep) join its lane: the running balance moves with each, the window keeps the last
    /// thirteen, and the tip leaves for the nodes within two seconds.
    func add(_ moves: [MTCoinEntry], book balance: Int) {
        guard !moves.isEmpty, var t = lane() else { return }
        for e in moves where Self.bore(e) {
            guard let k = Self.kinds.firstIndex(of: e.k), 0 < e.c, [e.ref, e.peer ?? "", e.on ?? ""].allSatisfy({ s in s.utf8.count <= 1024 }) else { continue }
            let signed = k < 2 ? Int64(e.c) : -Int64(e.c)
            let (b, over) = (t.links.last?.b ?? 0).addingReportingOverflow(signed)
            guard !over else { continue }
            t.links.append(Link(n: (t.links.last?.n ?? 0) + 1, at: MTTimeChain.ms(e.at), k: UInt8(k), c: UInt64(e.c), b: b,
                                ref: e.ref, peer: e.peer ?? "", on: e.on ?? ""))
            if Self.depth < t.links.count { t.prev = Self.seal(t.prev, t.links.removeFirst()) }
        }
        t.seen = Int64(balance)
        t.heard = MTCoinVault.shared.heard
        tip = t
        if let u = MTCoinPlace.file(Self.file) {
            let d = Self.encode(t)
            disk.async { MTDiskDoor.write(d, to: u, "coin-tip", options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]) }
        }
        soonPut()
    }

    /// THE LANE CARRIES WHAT THE DEVICE BORE (the author's «yes» 04.10.2026 14:16 UTC to variant (a)): a letter's coin and a coin
    /// letter reach every device of the words by the letter itself and the book counts each once by its name, so they ride no lane
    /// -- a sum of lanes would count them once a device; the lane carries what this device alone bore: the Pantheon, the VPN wall,
    /// chess and its Timer, the pull, spending, sending, burning.
    static func bore(_ e: MTCoinEntry) -> Bool {
        let s = MTTimeChain.source(of: e)
        return !(e.k == .earn && (s == "chats" || s == "groups" || s == "channels")) && !(e.k == .receive && s != "chess")
    }

    /// The tips leave at most once in two seconds: the moves of those seconds ride one piece.
    private func soonPut() {
        guard !putDue else { return }
        putDue = true
        let wait = max(0.3, putAt + 2 - Date().timeIntervalSince1970)
        DispatchQueue.main.asyncAfter(deadline: .now() + wait) { Task { @MainActor in await MTTimeChainTip.shared.put() } }
    }
    private func put() async {
        putDue = false
        if putting { again = true; return }
        putting = true
        defer { putting = false; if again { again = false; soonPut() } }
        putAt = Date().timeIntervalSince1970
        guard let t = tip, let k = MTCoinVault.mine(),
              let sealed = try? ChaChaPoly.seal(Self.encode(t), using: k.seal, authenticating: Self.aad).combined else { return }
        let token = MontanaHomeNode.hex(k.tip)
        let id = MontanaHomeNode.hex(Data(SHA256.hash(data: sealed)))
        var laid = 0
        for door in MontanaWakePush.oneDoorPerNode(MontanaWakePush.orderedBases(for: "vault")) {
            // A piece named in its own replace would be taken off and not laid again (the node checks before it deletes).
            let gone = Array(stale.union(mine[door].map { p in [p] } ?? [])).filter { p in p != id }
            let (code, o) = await MTSeedVault.post(door + "/vault-put", ["token": token, "blob": sealed.base64EncodedString(), "replace": gone], timeout: 10)
            guard code == 200, let piece = o?["piece"] as? String else { continue }
            mine[door] = piece
            opened[piece] = t.lane
            laid += 1
        }
        if 0 < laid { stale = [] }
        MontanaTrace.markFolded("tip_put", "n=\(t.links.last?.n ?? 0) b=\(t.links.last?.b ?? 0) bytes=\(sealed.count) doors=\(laid)", window: 60)
    }

    /// The other devices' tips in one round trip to the first node that answers: a lane's new links join the book by their names;
    /// a lane further behind than the window, or a link whose seal does not follow the head this device took, asks the book.
    func gather(why: String) async {
        guard !getting, let k = MTCoinVault.mine() else { return }
        let gen = MTCoinBook.generation   // the coin audit's second point: a seat moved during the wait joins nothing
        getting = true
        defer { getting = false }
        if !checked { checked = true; MontanaTrace.mark("tip_self", "ok=\(Self.selfCheck() ? 1 : 0)") }
        let own = lane()?.lane
        let token = MontanaHomeNode.hex(k.tip)
        var fresh: [MTCoinEntry] = [], lanes = 0, gap = false, broken = 0, answered = false
        for door in MontanaWakePush.oneDoorPerNode(MontanaWakePush.orderedBases(for: "vault")) {
            guard case let (200, o?) = await MTSeedVault.post(door + "/vault-get", ["token": token, "have": Array(opened.keys.prefix(256))], timeout: 6),
                  let held = o["held"] as? [String] else { continue }
            guard gen == MTCoinBook.generation else { MontanaTrace.mark("tip_get", "why=\(why) the seat moved -- nothing joined"); return }
            answered = true
            for x in (o["pieces"] as? [[String: Any]]) ?? [] {
                guard let id = x["piece"] as? String, let b = (x["blob"] as? String).flatMap({ s in Data(base64Encoded: s) }),
                      MontanaHomeNode.hex(Data(SHA256.hash(data: b))) == id,   // a piece is its own name
                      let box = try? ChaChaPoly.SealedBox(combined: b),
                      let plain = try? ChaChaPoly.open(box, using: k.seal, authenticating: Self.aad),
                      let t = Self.decode(plain), t.lane.count == 16 else { continue }
                opened[id] = t.lane
                if t.lane == own {
                    if mine[door] != id { stale.insert(id) }
                    continue
                }
                lanes += 1
                guard let first = t.links.first, let last = t.links.last else { continue }
                let seals = Self.chain(t)
                let had = heads[t.lane]
                guard Self.whole(t), Self.follows(had, t, seals) else { broken += 1; gap = true; continue }
                guard (had?.n ?? 0) < last.n else { continue }
                if (had?.n ?? 0) + 1 < first.n { gap = true }   // further behind than the window: the book carries the rest
                fresh += t.links.filter { l in (had?.n ?? 0) < l.n }.map(Self.entry)
                heads[t.lane] = (last.n, seals[seals.count - 1])
                if t.heard, seenAt < last.at { seenAt = last.at; seen = Int(t.seen) }
            }
            let standing = Set(held)
            opened = opened.filter { e in standing.contains(e.key) }   // a piece no node keeps is forgotten here too
            break
        }
        guard answered else { return }
        let joined = fresh.isEmpty ? 0 : MTLocalCoinLedger.shared.whole.join(fresh)
        if gap { MTCoinVault.shared.soon("tip", after: 1) }
        let kv = "why=\(why) lanes=\(lanes) joined=\(joined) gap=\(gap ? 1 : 0) broken=\(broken) seen=\(seen ?? -1)"
        if 0 < joined || gap { MontanaTrace.mark("tip_get", kv) } else { MontanaTrace.markFolded("tip_get", kv, window: 60) }
    }

    // MARK: the bytes, little-endian: the format 1, the lane (16), the seen balance (i64), heard (u8), prev (32), the count (u8), the
    // links; a link: n (u32), at in ms (i64), the kind (u8), the coins (u64), the running balance (i64), then ref, peer and on, each a
    // u16 length and its UTF-8.
    nonisolated static func encode(_ t: Tip) -> Data {
        var d = Data([1])
        d.append(t.lane); put(&d, t.seen); d.append(t.heard ? 1 : 0); d.append(t.prev); d.append(UInt8(t.links.count))
        for l in t.links { d.append(bytes(l)) }
        return d
    }
    nonisolated static func bytes(_ l: Link) -> Data {
        var d = Data()
        put(&d, l.n); put(&d, l.at); d.append(l.k); put(&d, l.c); put(&d, l.b)
        for s in [l.ref, l.peer, l.on] { let u = Data(s.utf8); put(&d, UInt16(u.count)); d.append(u) }
        return d
    }
    nonisolated private static func put<T: FixedWidthInteger>(_ d: inout Data, _ v: T) {
        withUnsafeBytes(of: v.littleEndian) { b in d.append(contentsOf: b) }
    }
    nonisolated static func decode(_ d: Data) -> Tip? {
        var r = Reader(d)
        guard r.u8() == 1, let lane = r.take(16), let seen: Int64 = r.int(), let heard = r.u8(), let prev = r.take(32),
              let count = r.u8(), Int(count) <= depth else { return nil }
        var t = Tip(lane: lane, seen: seen, heard: heard == 1, prev: prev)
        for _ in 0..<count {
            guard let n: UInt32 = r.int(), let at: Int64 = r.int(), let k = r.u8(), let c: UInt64 = r.int(), let b: Int64 = r.int(),
                  let ref = r.text(), let peer = r.text(), let on = r.text() else { return nil }
            t.links.append(Link(n: n, at: at, k: k, c: c, b: b, ref: ref, peer: peer, on: on))
        }
        return r.done ? t : nil
    }
    private struct Reader {
        let d: Data
        var i: Int
        init(_ d: Data) { self.d = d; i = d.startIndex }
        mutating func take(_ n: Int) -> Data? {
            guard n <= d.endIndex - i else { return nil }
            defer { i += n }
            return d.subdata(in: i..<(i + n))
        }
        mutating func u8() -> UInt8? { take(1)?.first }
        mutating func int<T: FixedWidthInteger>() -> T? {
            take(MemoryLayout<T>.size).map { b in b.withUnsafeBytes { p in T(littleEndian: p.loadUnaligned(as: T.self)) } }
        }
        mutating func text() -> String? {
            guard let n: UInt16 = int(), let b = take(Int(n)) else { return nil }
            return String(data: b, encoding: .utf8)
        }
        var done: Bool { i == d.endIndex }
    }

    // MARK: the chain: a link's seal is SHA-256 over the seal before it and the link's bytes, so the head seals the lane to its birth.
    nonisolated static func seal(_ prev: Data, _ l: Link) -> Data {
        var b = prev
        b.append(bytes(l))
        return Data(SHA256.hash(data: b))
    }
    nonisolated static func chain(_ t: Tip) -> [Data] {
        var prev = t.prev, out: [Data] = []
        for l in t.links { prev = seal(prev, l); out.append(prev) }
        return out
    }
    /// The window counts on: every link numbered after the one before, its balance the one before's and its own move.
    nonisolated static func whole(_ t: Tip) -> Bool {
        for (i, l) in t.links.enumerated() {
            guard Int(l.k) < kinds.count, 0 < l.c, l.c <= UInt64(Int.max) else { return false }
            guard 0 < i else { continue }
            let p = t.links[i - 1]
            let (b, over) = p.b.addingReportingOverflow(l.signed)
            guard l.n == p.n + 1, !over, b == l.b else { return false }
        }
        return true
    }
    /// The window follows the head this device took of that lane: the seal at that link is the one taken, or the window begins right
    /// after it. A lane never taken follows by itself.
    nonisolated static func follows(_ had: (n: UInt32, hash: Data)?, _ t: Tip, _ seals: [Data]) -> Bool {
        guard let had, let first = t.links.first else { return true }
        if had.n + 1 == first.n { return t.prev == had.hash }
        if first.n <= had.n, let i = t.links.firstIndex(where: { l in l.n == had.n }) { return seals[i] == had.hash }
        return true   // further behind than the window: nothing to compare, the book carries the rest
    }
    /// The bytes read back as they were written: thirteen links of every kind, a peer on every other one, the seal followed from the
    /// sixth -- a writer and a reader that disagree on an order, a width or a length fail here, on the phone, in the diary.
    nonisolated static func selfCheck() -> Bool {
        var t = Tip(lane: Data((0..<16).map { i in UInt8(i) }), seen: 13, heard: true)
        var b: Int64 = 0
        for n in 1...UInt32(depth) {
            let k = UInt8(n % 5), c = UInt64(n) * 1_000_003
            b += k < 2 ? Int64(c) : -Int64(c)
            t.links.append(Link(n: n, at: 1_759_000_000_000 + Int64(n), k: k, c: c, b: b, ref: "r" + String(n), peer: n % 2 == 0 ? "a:" + String(n) : "", on: ""))
        }
        guard let back = decode(encode(t)) else { return false }
        return back.lane == t.lane && back.seen == t.seen && back.heard && back.prev == t.prev && back.links == t.links && whole(back)
            && follows((t.links[5].n, chain(t)[5]), back, chain(back)) && !follows((t.links[5].n, chain(t)[4]), back, chain(back))
    }
    nonisolated static func entry(_ l: Link) -> MTCoinEntry {
        MTCoinEntry(k: kinds[Int(l.k)], c: Int(l.c), ref: l.ref, peer: l.peer.isEmpty ? nil : l.peer, on: l.on.isEmpty ? nil : l.on,
                    at: Double(l.at) / 1000)
    }
}

/// THE VPN WALL, READ AS HISTORY (the author's words 04.10.2026 14:13-14:24 UTC began it: «while the VPN tunnel is on and alive, the
/// same auto minting as in the wallet»): up to the time cut the living tunnel's seconds were minted into this phone's book under this
/// name; since build 2320 nothing local mints (the author's decision 375 «a»). A living tunnel is presence, and presence is the
/// chain's to mint (fold-7, MTCoinTx.beHere): the tunnel's rise, the app's return and the wallet's opening tell the chain the person
/// is here and run the beat that shows its seconds (MTMintBeat).
enum MTVPNWallMint {
    static let refPrefix = "vpnwall:"
    /// The app stands in front of the person and a VPN is up -- Montana's tunnel or another app's (MTForeignVPN). Not «active» but
    /// «not in the background»: the scene's return reaches count() before the application's state turns active (T3 05.10 11:31Z).
    @MainActor static var wanted: Bool {
        UIApplication.shared.applicationState != .background && MTApps.vpn?.anyTunnel == true
    }
    /// The app came to the screen, the wallet opened or the tunnel rose: the beat runs and the chain hears the person (fold-7).
    @MainActor static func count() { MTMintBeat.run(); MTCoinTx.beHere() }
}

/// THE PULL SWITCHES THE AUTO MINTING ON (the author's words 04.10.2026 00:52 and 01:18 UTC: «pulling the wallet's page, as the time
/// panel does, calls the coin for a forced refresh of the tops and the activation of the auto minting once a second»; «at such a
/// refresh switch the auto minting on: every second coins by the box's level»): a pull let go past the coin's trigger reads the tops
/// again and runs the beat that shows the chain's seconds while the wallet stands open (MTMintBeat); since build 2320 it mints
/// nothing itself (the author's decision 375 «a»).
/// THE PERSON ENDS IT, NO CLOCK (the author's word 04.10.2026 10:33 UTC: «it must not stop until I touch the coin myself or leave
/// the wallet's page -- it mints only while the wallet's screen is active, without taps on it, and deactivates at any action; all
/// three ran auto and stopped by themselves»; T2 10:29:49-10:30:49Z: on, then off by its window of sixty seconds): the page leaving and the
/// screen locked stop it; nothing else does -- no touch (the author's word 04.10.2026 21:53 UTC: «I did not touch; only leaving the
/// page or locking the screen, touches do not reset the auto minting»; T2 and T3 21:45Z stopped why=touch by a tap on a row). The pull tells the person's pairs the balance now, at most once in fifteen seconds, so their tops move and a
/// hand that pulls on does not flood the queue. The coins are the Pantheon's, the wallet's game.
@MainActor final class MTWalletPull: ObservableObject {
    static let shared = MTWalletPull()
    static let refPrefix = MTPantheon.refPrefix + "pull-"
    @Published private(set) var on = false
    private var told: Double = 0

    func fire() {
        let now = Date().timeIntervalSince1970
        tellPairs(now)
        Task { await MontanaWakePush.sweepPresence(quiet: true) }   // the tops read again from the nodes at once
        Task { await MTTopNet.shared.read() }
        guard !on else { return }
        on = true
        MontanaTrace.mark("wallet_pull", "auto on")
        MTMintBeat.run()   // its seconds ride the one beat of the minting by the second (04.10 18:08)
    }
    /// The page left or the screen locked: the minting stops with it.
    func stop(why: String) {
        guard on else { return }
        on = false
        MontanaTrace.mark("wallet_pull", "auto off why=\(why)")
    }
    private func tellPairs(_ now: Double) {
        guard 15 <= now - told, let store = ChatStore.live else { return }
        told = now
        for c in store.listChats() where !c.isGroup { if let conv = c.convId { E2E.shared.tellBalance(to: conv) } }
    }
}

/// ONE BEAT FOR THE CHAIN'S SECONDS ON THE SCREEN (the author's word 04.10.2026 15:08 UTC, T2: «the minting's animation must not
/// double, only give the sum in the plus animation»; 23.10.2026 20:2x UTC: «in the client the minting shows just as before, only it
/// all happens at the core's level»): while the wallet's pull or a living VPN wants it, the beat raises the chain's seconds once a
/// second with their sum (MTCoinSplit.beat, MTCoinFlash.rise). It mints nothing (the author's decision 375 «a», build 2320) and
/// stops by itself when neither wants it.
@MainActor enum MTMintBeat {
    private static var beating: Task<Void, Never>?
    static var beats: Bool { beating != nil }
    static func run() {
        guard beating == nil else { return }
        beating = Task { @MainActor in
            while !Task.isCancelled {
                guard MTWalletPull.shared.on || MTVPNWallMint.wanted else { break }
                MTCoinSplit.shared.beat()
                try? await Task.sleep(nanoseconds: UInt64(MTCoinFlash.gather * 1_000_000_000))
                MTCoinFlash.shared.rise()
                try? await Task.sleep(nanoseconds: UInt64((1 - MTCoinFlash.gather) * 1_000_000_000))
            }
            beating = nil
            MTCoinFlash.shared.rise()   // the last second's coins rise too
        }
    }
}

/// ONE MOVE OF COINS on this phone's book: a coin earned by a letter of the ribbon, coins received in a chat or on a letter,
/// coins given on a letter or a post, coins sent to a person. The amount is whole coins (one coin is one billionth of a
/// Montana) and always positive; the kind says which way it goes. `ref` is the move's own name -- a letter's wire name, the
/// name a reaction carries -- and a name is taken once, ever: a letter that lands twice, a word the lane repeats, a launch
/// that reads the book again, never pays twice.
struct MTCoinEntry: Codable, Hashable, Identifiable {
    enum Kind: String, Codable { case earn, receive, spend, send, burn }
    var k: Kind
    var c: Int
    var ref: String
    var peer: String? = nil
    var on: String? = nil      // the letter (its wire name) or the post («post:» + its id) the coins were given on
    var at: Double
    var id: String { k.rawValue + ":" + ref }
    var signed: Int { (k == .earn || k == .receive) ? c : -c }
    /// A NAME A RESTORE GIVES A LETTER NAMES NO MOVE (the author's words 09.10.2026 08:3x-08:4x UTC: "the balance swelled, this person
    /// never had 5 million -- check it, it is a hole"; "we have a cryptographic TimeChain: only unambiguous mathematics, and the
    /// restore must bring back the incomes and the expenses right"). A coin letter moves its coins once, under its wire name, the one
    /// name both phones hold. A restore names its copy of the letter anew (MTRestoredMid: the archive's "arc:", the keepers' "given:"),
    /// and the book credited the same letter again under that name: T1's book of 09.10 held 20 credits under "arc:", 5 316 382
    /// coins, beside the same letters' 22 credits under their wire names, 5 316 541, and the seed's vault had carried them to every
    /// device of the words (the balance 5 850 661 where the moves sum to 534 279). Every door of the book passes such a move -- the
    /// reading, the joining, the taking -- on every device alike.
    var restoredName: Bool { MTRestoredMid.holds(ref) }
    /// THE LETTER THE COINS STAND UNDER (MTLocalCoinLedger.coins(on:)), or nil. A bubble's own coin of the builds before the burning
    /// (MTCoinSend.pay) -- paid by the writer to the reader as a reaction word -- stands under no bubble: the author's word
    /// 05.10.2026 19:29 UTC, «in ordinary chats take away the coin under every message as a reaction», takes it from the bubbles
    /// sent before too, on both phones; the coins stay where the book moved them.
    var shownOn: String? {
        ref.hasPrefix(MTCoinSend.bubblePrefix) || ref.hasPrefix(MTCoinSend.receivedPrefix + MTCoinSend.bubblePrefix) ? nil : on
    }
    /// The coins this move stands under its letter with: a SEND that came back (MTCoinTx.backPrefix) is laid under the letter its
    /// SEND stood under and takes its coins from there, so a paid reaction no node took shows nothing under the letter.
    var shownCoins: Int { ref.hasPrefix(MTCoinTx.backPrefix) ? -c : c }
}

/// THE ONE DOOR OF THE COINS (the author's word 03.10 13:52: «an in-app coin core with no crypto core, behind one
/// protocol»). Every reader and writer of coins in the app speaks to this and to nothing else: the wallet, the paid
/// reactions, the coin letters in a chat. THE SEAM FOR THE REAL MONEY IS THIS PROTOCOL: the day the
/// protocol core opens this person's wallet and offers a door that mints for a letter and transfers between wallets
/// (montana_core.h has neither today), a second implementation answers here and MTCoinBook.ledger names it -- nothing
/// that calls these doors changes. Until then the book is LOCAL: kept on this phone, never a note of the core's wallet.
@MainActor protocol MTCoinLedger: AnyObject {
    var balance: Int { get }
    var entries: [MTCoinEntry] { get }
    // NO DOOR OF THE BOOK MINTS (the author's decision 375 «a», build 2320): earn, mint and the window of τ1 are gone -- only the
    // chain mints, 1 coin is 1 second (the word 11871); the old earned lines stand in the book as history.
    // NO DOOR OF THE BOOK BURNS (decision 383 «a», build 2322): a comment's four of five were the last burn; the old burned lines
    // stand in the book as history.
    /// Coins given on a letter or a post; refused (false) when the balance is short or the name was taken.
    func spend(_ coins: Int, on target: String, peer: String, ref: String) -> Bool
    /// Coins sent to a person in a coin letter; refused (false) when the balance is short or the name was taken.
    func send(_ coins: Int, to peer: String, ref: String) -> Bool
    /// Coins that arrived, credited once by their name; false when the name was taken already.
    @discardableResult func receive(_ coins: Int, from peer: String, ref: String, on target: String?) -> Bool
    /// How many coins stand on a letter or a post, given and received alike.
    func coins(on target: String) -> Int
}

/// THE BOOK'S CHESS LINES OF THE BUILDS BEFORE (COMPAT-LOCAL; the author's word 29.10.2026 19:31 UTC: «in chess there must be no
/// crediting of coins»): chess and its Timer write no coin; the names their lines carried in the book of the builds before are read
/// here only so a person's history keeps telling where those coins came from. Nothing here writes or moves a coin.
enum MTCoinLegacy {
    nonisolated static let chessNames = ["chess:", "chess-won:", "chess-lost:", "chess-pot:", "chess-stake:", "chess-back:"]
    nonisolated static func chess(_ ref: String) -> Bool { chessNames.contains { ref.hasPrefix($0) } }
    nonisolated static func timer(_ ref: String) -> Bool { ref.hasPrefix("timer:") }   // COMPAT-LOCAL: a name of this phone's own book, never a word on the wire
    /// A call's seconds minted by the builds before (the author's word 29.10.2026 19:31 UTC: «and at a call too»); a call writes no coin.
    nonisolated static func call(_ ref: String) -> Bool { ref.hasPrefix("callmint:") }   // COMPAT-LOCAL: a name of this phone's own book, never a word on the wire
}

/// The app's one book of coins, today (see MTCoinLedger for the seam).
enum MTCoinBook {
    @MainActor static var ledger: any MTCoinLedger { MTLocalCoinLedger.shared.whole }
    /// THE SMALL SPEND (the wallet's history folds them, MTWalletScreen): a coin on a letter or a post carries at most thirteen.
    /// Not a rate: since 19.10.2026 a second of life mints one coin, all minting together (price, below).
    static let smallSpend = 13
    /// THE PRICE OF A SECOND, THE ONE OWNER OF THE FUNCTION «1 COIN = 1 SECOND» (point 11; the author's words 05.10.2026 11:17 UTC:
    /// «a second = 1 coin everywhere»; 19.10.2026 12:3x: «the ceiling, the invariant -- nothing else can mint or accelerate it»;
    /// 13:4x: «one owner of the function 1 coin = 1 second, and that is all»): one coin, the most a second mints, every door
    /// together (MTLocalCoinLedger.priced) -- a person's hour is 3 600 coins and their personal rate is read by it (MTHourWorth, MTPersonalRate).
    static let price = 1
    /// THE TICKER OF THE MONTANA TIME COIN (the constitution of the chain, point 12, the author's word 04.10.2026 14:31 UTC): one
    /// symbol in every language, beside the balance.
    static let ticker = "$TCM"
    /// THE BOOK'S GENERATION (the author's word «fix all points in order» 05.10.2026 18:4x UTC, the coin audit's second point): one
    /// more at every seat's move, before anything is read again. A gather begun under the person who left took their key, waited on
    /// the nodes, and then read the book of the person seated -- laying it over every piece of the old seed (the whole book lost
    /// to a restore on another phone). A gather compares this after every wait and writes nothing once it moved.
    @MainActor static var generation: Int { MTSeatTurn.now }   // the seat's turn, shared with the person's chain (MTSeatTurn)
    /// A PERSON LIFTED INTO THE SEAT READS THEIR OWN COINS (the author's word 04.10.2026 00:38 UTC): every owner of coins on this phone
    /// lets the person who left go and reads the folder of the person seated (MTCoinPlace) -- the chains first, so the book's past
    /// joins the seated person's chains.
    @MainActor static func reread() {
        MTCoinVault.shared.forget()
        MTTimeChainTip.shared.reread()
        MTTimeChain.forget()
        MTPersonChain.shared.reread()
        MTLocalCoinLedger.shared.reread()
        MTCoinBoard.shared.reread()
        MontanaTrace.mark("coin_book", "reread")
    }
    /// NO LIMIT BUT THE BALANCE AND ONE AT LEAST (the author's word 03.10): a move of any whole number of coins from one up; the
    /// one bound is the arithmetic's -- the count must still fit the book's integer beside the balance -- never a rule of the coin.
    static func fits(_ coins: Int, beside balance: Int) -> Bool { 0 < coins && !balance.addingReportingOverflow(coins).overflow }
}

/// A WALK OF THE CHAIN WRITES ONLY ITS OWN PERSON (the critic 19.10.2026 on T2; the author's words 20:25 «a separate person, wholly
/// separate, with none of this mixing» and 20:4x «build by the constitution with chains of time, strictly with no races allowed»): a
/// walk asks the nodes and waits, and a seat that moves during the wait seats another person behind the same book, the same folder
/// and the same key's name. The walk takes its seat at its first step; after every wait it reaches the book, the person's files and
/// the records it signs only through that seat. Once the seat moved it writes nothing: what it had begun waits in the folder of its
/// own person, which moved with them, and their own walks decide it when they sit again.
@MainActor struct MTCoinSeat {
    let generation = MTCoinBook.generation
    var stands: Bool { generation == MTCoinBook.generation }
    var book: MTLocalCoinLedger? { stands ? MTLocalCoinLedger.shared.whole : nil }
}

/// THE LOCAL BOOK: one line of JSON per move, appended, in Application Support (protected until the first unlock, as the
/// chat coins' names are). The balance and the totals are the sum of the lines, recounted at launch -- the file is the one
/// truth, the numbers are its reading.
/// THE PERSON'S COINS LIVE IN THE PERSON'S FOLDER (the author's word 04.10.2026 00:38 UTC: «I came in with another account on T1,
/// another seed, and the wallet's balance of the other account is here -- a gross violation»). The book, its TimeChains and the
/// chats' tally lay among the phone's own files, so a seat's move (MTSeats) parked the person and left their coins to the next
/// one. They live in Montana/Coins, a folder of the person seated (SeedScope.seatFolders): parked with the person, lifted with
/// them. The files of the builds before belong to the person who held the phone when the book was born -- the first seat born
/// before the book's first move -- and are laid into that person's folder once, the first time the place is asked for.
enum MTCoinPlace {
    static let book = "coin-ledger.jsonl"   // NOT-UI: the book's file name
    static let tally = "chat-coins.txt"     // NOT-UI: the chats' tally
    private static let montana = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
        .appendingPathComponent("Montana", isDirectory: true)
    static let dir: URL? = settle(montana?.appendingPathComponent("Coins", isDirectory: true))
    static func file(_ name: String) -> URL? { dir?.appendingPathComponent(name) }
    /// THE BOOK OF A PERSON FORGOTTEN LEAVES WITH THEM (the author's word «fix all points in order» 05.10.2026 18:4x UTC, the coin
    /// audit's eighth point): «Forget the device» with no other seat left this folder in place, and the next seed's book was the
    /// forgotten one's -- read, shown and laid on the nodes under the new seed. The folder's files are set aside whole, under the
    /// moment of the forgetting, and nothing reads them again: the coins ride their own seed on the nodes (MTCoinVault), and this
    /// copy is the phone's last word for whatever a node had not heard yet.
    private static let forgottenRoot = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
        .appendingPathComponent("Montana", isDirectory: true).appendingPathComponent("CoinsForgotten", isDirectory: true)
    static func setAside() {
        guard let dir, let forgottenRoot else { return }
        let fm = FileManager.default
        let names = (try? fm.contentsOfDirectory(atPath: dir.path)) ?? []
        guard !names.isEmpty else { return }
        let place = forgottenRoot.appendingPathComponent(String(Int64(Date().timeIntervalSince1970 * 1000)), isDirectory: true)
        try? fm.createDirectory(at: place, withIntermediateDirectories: true,
                                attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        var moved = 0
        for name in names where (try? fm.moveItem(at: dir.appendingPathComponent(name), to: place.appendingPathComponent(name))) != nil { moved += 1 }
        MontanaTrace.mark("coin_place", "forgotten set aside=\(moved)/\(names.count)")
    }

    private static func settle(_ coins: URL?) -> URL? {
        guard let montana, let coins else { return nil }
        let fm = FileManager.default
        let sealed: [FileAttributeKey: Any] = [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        try? fm.createDirectory(at: coins, withIntermediateDirectories: true, attributes: sealed)
        let names = ((try? fm.contentsOfDirectory(atPath: montana.path)) ?? []).filter { n in
            n == book || n == tally || (n.hasPrefix("chain-") && n.hasSuffix(".jsonl"))
        }
        guard !names.isEmpty else { return coins }
        let first = firstMove(montana.appendingPathComponent(book))
        let seats = MTSeats.book()
        let owner = seats.seats.filter { s in first.map { at in s.born <= at } ?? true }.min { a, b in a.born < b.born }?.id
        // A BOOK WHOSE OWNER IS NOT KNOWN STAYS WHERE IT STANDS (the author's word «fix all points in order» 05.10.2026 18:4x UTC,
        // the coin audit's seventh point): born is written at a seat's first move -- after the book's first move -- so with two
        // seats or more the filter found nobody and the book went to whoever sat. It moves only to a person the seats name.
        if owner == nil, 1 < seats.seats.count {
            MontanaTrace.mark("coin_place", "owner unknown -- the root book stays")
            return coins
        }
        var place = coins
        if let owner, owner != seats.active { place = MTSeats.shelf(folder: "AS:Montana/Coins", seat: owner) }
        try? fm.createDirectory(at: place, withIntermediateDirectories: true, attributes: sealed)
        var laid = 0
        for n in names where !fm.fileExists(atPath: place.appendingPathComponent(n).path) {
            if (try? fm.moveItem(at: montana.appendingPathComponent(n), to: place.appendingPathComponent(n))) != nil { laid += 1 }
        }
        MontanaTrace.mark("coin_place", "laid=\(laid)/\(names.count) owner=\(place == coins ? "seated" : "parked")")
        return coins
    }
    /// The moment of the book's first move, from its first line.
    private static func firstMove(_ url: URL) -> Double? {
        guard let h = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? h.close() }
        guard let d = try? h.read(upToCount: 4096), let line = String(decoding: d, as: UTF8.self).split(separator: "\n").first,
              let e = try? JSONDecoder().decode(MTCoinEntry.self, from: Data(line.utf8)) else { return nil }
        return e.at
    }
}

/// THE BOOK'S ONE SUM (the coin audit's ninth point, 05.10.2026 18:4x UTC): the tallies saturate, never trap -- a sum past the
/// integer is shown at its edge, and the app lives. ONE COIN, ONE SECOND (the author's word 02.11.2026 16:14 UTC, link 14629: «only
/// 1 coin is 1 second, no other way named»): the counts by source -- the Pantheon's taps, chess, the VPN wall, the chats -- stood
/// here for the wallet's Minting section and went with it; only the chain mints, by the seconds a person is here.
struct MTCoinCounts {
    static func plus(_ a: Int, _ b: Int) -> Int {
        let (s, over) = a.addingReportingOverflow(b)
        return over ? (0 < b ? Int.max : Int.min) : s
    }
}

@MainActor final class MTLocalCoinLedger: ObservableObject, MTCoinLedger {
    static let shared = MTLocalCoinLedger()
    @Published private(set) var entries: [MTCoinEntry] = []
    @Published private(set) var balance = 0
    @Published private(set) var onTarget: [String: Int] = [:]
    /// The highest level of π the balance has filled since the book was read (MTPiLevels): a level reached for the first time is a link.
    private var level = 0
    private var taken = Set<String>()
    /// The pairs whose other end holds these words, as the book says (MTOwnWords): read from the moves at every reading and kept with
    /// every move taken or joined.
    private(set) var ownPeers = Set<String>()
    private var file: URL? { MTCoinPlace.file(MTCoinPlace.book) }
    private let disk = DispatchQueue(label: "montana.coin-ledger", qos: .utility)

    /// The book is born at the app's start (ContentView), so its one reading lands before anyone asks for it.
    static func warm() { _ = shared }

    private init() {
        begin()
        // What waits for the second's write is on disk the moment the app leaves the screen, in that same turn, and the seed's
        // nodes are asked for it at once (the author's word «fix all points in order» 05.10.2026 18:4x UTC, the coin audit's
        // fifth point: an asynchronous write and an upload a minute later lost the open windows to a process ended in the
        // background, and to a phone lost after it, what no node held yet).
        NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                MTLocalCoinLedger.shared.writeWhole()
                MTCoinVault.shared.soon("leave", after: 1)
            }
            MTTimeChain.flush()
        }
    }
    /// The person lifted into the seat: the book of the person who left is let go and the seated person's book is read
    /// (MTCoinBook.reread).
    func reread() {
        flush()   // the person who left keeps every move of their last second, in their own book
        entries = []; taken = []; onTarget = [:]; ownPeers = []
        balance = 0; level = 0
        begin()
    }

    /// THE BOOK IS READ ONCE, OFF THE SCREEN'S THREAD, AND SHOWN AT ONCE (the author's words 04.10.2026 10:04-10:10 UTC: «at 10:04
    /// on T1 I open the wallet and it opens long, from a hang -- close it by construction»; «build by constitution 0»). T1's book
    /// of 19 358 moves was read on the main thread the first time anything asked for it -- the wallet's opening, 3.7 s of a still
    /// screen: a decoder made anew for every line, every move appended to a published array that copied itself whole, and a task
    /// of the balance's word queued on the main actor for every move. Now the file is decoded on the book's own queue from the
    /// book's birth, folded into plain sums and published as one assignment; a door of the book asked before the reading lands
    /// waits for that one reading (whole), never for a second.
    private final class Reading: @unchecked Sendable {   // written on the book's queue only, read on the main actor after that queue
        var moves: [MTCoinEntry] = []
        var taken = Set<String>()
    }
    private var reading: Reading?
    var whole: MTLocalCoinLedger { landed(); return self }

    private func begin() {
        let r = Reading()
        reading = r
        let file = self.file
        disk.async {
            (r.moves, r.taken) = MTLocalCoinLedger.decode(file)
            DispatchQueue.main.async { MainActor.assumeIsolated { MTLocalCoinLedger.shared.adopt(r) } }
        }
    }
    private func landed() {
        guard let r = reading else { return }
        let asked = Date()
        // MAIN-SAFE-SYNC: only a door asked before the book's one reading lands waits, and only for that reading, begun at the
        // app's start (warm); the main thread used to do the same reading in full by itself (3.7 s on T1, 04.10), and the queue
        // holds nothing else but the appends of a second's moves. The diary says how long a door waited.
        disk.sync {}
        MontanaTrace.mark("coin_book", "waited ms=\(Int(Date().timeIntervalSince(asked) * 1000))")
        adopt(r)
    }
    /// A line cut short by an ended process is no move: only a whole line counts, once by its name, while the sum still fits.
    nonisolated private static func decode(_ file: URL?) -> ([MTCoinEntry], Set<String>) {
        // ONE BAD BYTE COSTS ONE LINE, NEVER THE BOOK (the author's word «fix all points in order» 05.10.2026 18:4x UTC, the coin
        // audit's tenth point): the book was read as one UTF-8 text, and a single invalid byte read it as nothing -- an empty book
        // until the nodes filled it again. It is read as bytes, and every line is decoded alone.
        guard let file, let data = try? Data(contentsOf: file) else { return ([], []) }
        let decoder = JSONDecoder()
        var moves: [MTCoinEntry] = []
        var taken = Set<String>()
        var sum = 0, passed = 0, passedCoins = 0
        defer { if 0 < passed { MontanaTrace.mark("coin_book", "passed restored names=\(passed) coins=\(passedCoins)") } }
        for line in data.split(separator: 0x0A) {
            guard let e = try? decoder.decode(MTCoinEntry.self, from: Data(line)), 0 < e.c, !taken.contains(e.id) else { continue }
            if e.restoredName { passed += 1; passedCoins += e.c; continue }
            let (next, over) = sum.addingReportingOverflow(e.signed)
            guard !over else { continue }
            sum = next
            moves.append(e)
            taken.insert(e.id)
        }
        return (moves, taken)
    }
    /// A book's balance as its file holds it -- a person's on this phone's shelf (MTSeats.shelfCoins) -- read off the screen's thread.
    nonisolated static func balance(of file: URL) -> Int { decode(file).0.reduce(0) { s, e in MTCoinCounts.plus(s, e.signed) } }
    private func adopt(_ r: Reading) {
        guard reading === r else { return }   // a reading of the person who left the seat
        reading = nil
        var sum = 0, onTarget: [String: Int] = [:], level = 0
        var levels: [(n: Int, at: Double)] = []
        for e in r.moves {
            sum += e.signed
            if let on = e.shownOn { onTarget[on, default: 0] += e.shownCoins }
            let place = MTPiLevels.place(sum)
            if level < place {
                for n in (level + 1)...place { levels.append((n, e.at)) }
                level = place
            }
        }
        entries = r.moves; taken = r.taken; balance = sum; self.onTarget = onTarget; self.level = level
        ownPeers = Self.own(r.moves, names: r.taken)
        MontanaTrace.mark("coin_book", "read moves=\(r.moves.count) balance=\(sum) local=1")
        for l in levels { MTTimeChain.note("pi", kind: "level", coins: l.n, ref: "level:" + String(l.n), at: l.at) }
        // THE CHAINS TAKE THE BOOK'S PAST ONCE (04.10): every move written before the chains stood joins its chain in the book's
        // order; a move the chain already holds is passed by its name.
        MTTimeChain.appendPast(r.moves)
        MTCoinSplit.shared.told()
        MTCoinVault.shared.soon("read", after: 1)
        MTCoinSend.returnUndeliverable(self)
    }

    /// THE MOVES OF THE SEED'S OTHER DEVICES (MTCoinVault): taken once by their names into this book and this phone's file, in one
    /// assignment -- a device restored by its words takes the whole book here; they are on the nodes already and ride no piece back.
    @discardableResult func join(_ moves: [MTCoinEntry]) -> Int {
        var all = entries, names = taken, sum = balance, on = onTarget
        var fresh: [MTCoinEntry] = []
        for e in moves where 0 < e.c && !e.restoredName && !names.contains(e.id) {
            let (next, over) = sum.addingReportingOverflow(e.signed)
            guard !over else { continue }
            sum = next
            all.append(e); names.insert(e.id)
            if let t = e.shownOn { on[t, default: 0] += e.c }
            fresh.append(e)
        }
        guard !fresh.isEmpty else { return 0 }
        entries = all; taken = names; balance = sum; onTarget = on
        ownPeers.formUnion(Self.own(fresh, names: names))
        MTCoinSplit.shared.told()
        reached(at: Date().timeIntervalSince1970)
        // A RESTORED DEVICE TAKES THE WHOLE BOOK IN ONE STROKE (15:51): nineteen thousand moves are encoded and written on the book's
        // queue, not on the screen's thread; their chains take them in one turn of their own queue.
        MTTimeChain.appendPast(fresh)
        if let file { let lines = fresh; disk.async { MTLocalCoinLedger.append(lines, to: file) } }
        MontanaTrace.mark("coin_book", "joined moves=\(fresh.count) balance=\(sum)")
        MTCoinSend.returnUndeliverable(self)
        return fresh.count
    }

    /// THE BALANCE NEVER WRAPS (the author's word «fix all points in order» 05.10.2026 18:4x UTC, the coin audit's ninth point): a
    /// coin letter of Int.max less the balance passed fits, and every later earning trapped on the sum -- the app died at any
    /// minting. Every move of the hand and the minting passes this one door; a move the integer cannot hold is refused here,
    /// before it is written.
    @discardableResult private func take(_ e: MTCoinEntry) -> Bool {
        guard !e.restoredName else {
            MontanaTrace.mark("coin_refused", "\(e.k.rawValue) coins=\(e.c) under a restored name")
            return false
        }
        let (next, over) = balance.addingReportingOverflow(e.signed)
        guard !over else {
            MontanaTrace.mark("coin_refused", "\(e.k.rawValue) coins=\(e.c) the balance cannot hold it")
            return false
        }
        entries.append(e)
        taken.insert(e.id)
        ownPeers.formUnion(Self.own([e], names: taken))
        balance = next
        if let on = e.shownOn { onTarget[on, default: 0] += e.shownCoins }
        MTCoinSplit.shared.told()
        reached(at: e.at)
        return true
    }
    /// THE BOOK SAYS WHICH PAIRS HOLD THESE WORDS (the author's words 06.10.2026 08:1x-08:2x UTC, MTOwnWords): one move of coins seen
    /// from both its ends -- a coin letter sent and credited under its one name, a paid reaction given and credited under its one
    /// name -- lies in one book only when both ends hold the same words, for the book is the union of one seed's devices; the pair of
    /// such a move is the words' own. The book of the iPhone 17 says it of the iPad from the first coin letter between them, 08:13:24Z.
    nonisolated static func own(_ moves: [MTCoinEntry], names: Set<String>) -> Set<String> {
        var out = Set<String>()
        for e in moves {
            guard let peer = e.peer, !peer.isEmpty else { continue }
            let twin: String
            switch e.k {
            case .send: twin = "receive:" + e.ref
            case .receive: twin = e.ref.hasPrefix("rc:") ? "spend:" + String(e.ref.dropFirst(3)) : "send:" + e.ref   // COMPAT-LOCAL: the book's own names, never a word on the wire
            case .spend: twin = "receive:rc:" + e.ref   // COMPAT-LOCAL: the book's own names, never a word on the wire
            case .earn, .burn: continue
            }
            if names.contains(twin) { out.insert(peer) }
        }
        return out
    }
    /// A LEVEL OF π REACHED IS A LINK (the author's word 04.10 00:51: «every new level on top, as comments in the TimeChain,
    /// revealing π as your balance»): the first time the balance fills a level, the level joins its chain, at the move's moment.
    private func reached(at moment: Double) {
        let place = MTPiLevels.place(balance)
        if level < place {
            for n in (level + 1)...place { MTTimeChain.note("pi", kind: "level", coins: n, ref: "level:" + String(n), at: moment) }
            level = place
        }
    }

    /// THE PERSON LEAVING THE SEAT KEEPS EVERY COIN OF THEIR LAST MINUTE (the author's word «fix all points in order» 05.10.2026
    /// 18:4x UTC, the coin audit's fourth point): the book and its chains are on disk in this turn, while the
    /// person's folder still stands -- the seat's park moves the folder, and the lines that waited for their second then found no
    /// folder, or the next person's (MTSeats.parkThenLift asks this before it parks).
    func writeWhole() { writeNow() }

    /// THE BOOK IS WRITTEN ONCE A SECOND, NOT ONCE A COIN (the author's word 04.10.2026 09:27 UTC: «check why the phone heats while
    /// minting actively, and do it by constitution 0»; the iPhone 15 Pro Max on 04.10: twenty thousand coins in a day, every one a
    /// file opened, written and closed twice -- the book and its TimeChain -- and a line of the diary). The moves of a second ride one
    /// write, in the file of the person they belong to; the app leaving the screen and a change of person write what waits at once.
    private var pending = Data()
    private var pendingFile: URL?
    private var flushDue = false
    private func keep(_ fresh: [MTCoinEntry], now: Bool = false) {
        MTTimeChain.appendPast(fresh)   // every new move joins its source's TimeChain (04.10), all of them in one turn of its queue
        MTTimeChainTip.shared.add(fresh, book: balance)   // and this device's lane, whose tip rides one round trip (04.10 16:34)
        guard let file, !fresh.isEmpty else { return }
        MTCoinVault.shared.soon(now ? "move" : "moves", after: now ? 1 : 60)   // a move between people reaches the seed's devices at once
        MTCoinTx.mintSoon()   // and the chain takes what the book holds above it within one window of τ1
        if let was = pendingFile, was != file { flush() }
        pendingFile = file
        for e in fresh {
            guard let d = try? JSONEncoder().encode(e) else { continue }
            pending.append(d); pending.append(0x0A)
        }
        if now { writeNow(); return }
        guard !flushDue else { return }
        flushDue = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.flush() }
    }
    /// A MOVE BETWEEN PEOPLE IS ON DISK BEFORE ANYONE HEARS OF IT (the author's word 04.10.2026 20:57 UTC: «sent 123 thousand coins
    /// from T3, they did not appear for her, and T3 was debited -- a gross breach of the constitution; close it by construction»).
    /// The iPhone 15 Pro Max credited them at 20:54:30Z in a background wake, and the process ended inside the second the book waits
    /// before it writes; the next launch read the book without them (209 216, then 86 216). A coin sent, received or given is
    /// written in the same turn, with every line that waited before it; the minting's lines keep their second.
    private func writeNow() {
        flushDue = false
        guard let file = pendingFile, !pending.isEmpty else { return }
        let data = pending
        pending = Data()
        // MAIN-SAFE-SYNC: the book's queue holds only appends of a second's lines; a coin between people waits for its own line.
        disk.sync { MTLocalCoinLedger.write(data, to: file) }
        MTTimeChain.flush()
    }
    func flush() {
        flushDue = false
        guard let file = pendingFile, !pending.isEmpty else { return }
        let data = pending
        pending = Data()
        disk.async { MTLocalCoinLedger.write(data, to: file) }
    }
    nonisolated private static func append(_ moves: [MTCoinEntry], to file: URL) {
        let encoder = JSONEncoder()
        var data = Data()
        for e in moves { if let d = try? encoder.encode(e) { data.append(d); data.append(0x0A) } }
        write(data, to: file)
    }
    /// The book's queue alone: lines appended to the book's file.
    nonisolated private static func write(_ data: Data, to file: URL) {
        guard !data.isEmpty else { return }
        if let h = try? FileHandle(forUpdating: file) {
            // A line cut short by an ended process is ended here first, so the next move stands on a line of its own and is never
            // swallowed by the broken one (the coin audit's tenth point).
            if let end = try? h.seekToEnd(), 0 < end {
                try? h.seek(toOffset: end - 1)
                let last = try? h.read(upToCount: 1)
                _ = try? h.seekToEnd()
                if last != Data([0x0A]) { try? h.write(contentsOf: Data([0x0A])) }
            }
            try? h.write(contentsOf: data); MTDiskDoor.count("coin-book", data.count)
            try? h.close()
        } else if !FileManager.default.fileExists(atPath: file.path) {
            // Born only where none stands: a book that stands but would not open is never written over.
            MTDiskDoor.write(data, to: file, "coin-book", options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
    }

    func spend(_ coins: Int, on target: String, peer: String, ref: String) -> Bool {
        move(.spend, coins, peer: peer, ref: ref, on: target)
    }

    func send(_ coins: Int, to peer: String, ref: String) -> Bool {
        move(.send, coins, peer: peer, ref: ref, on: nil)
    }
    /// A SEND given on a letter (a paid reaction, MTCoinTx.send3): its coins stand under that letter.
    func send(_ coins: Int, to peer: String, ref: String, on target: String?) -> Bool {
        move(.send, coins, peer: peer, ref: ref, on: target)
    }

    /// A COIN LETTER PROVEN DELIVERED TAKES ITS COINS AGAIN, WHATEVER THE BALANCE (the author's words 06.10.2026 09:3x-09:4x UTC: «close the double spends»; «the safety of the restore by the seed»): its
    /// coins came back while it was red (MTCoinSend.hold), the receiver credited it all the same, and its late receipt asks them
    /// again. A refusal on a short balance left them in two books for ever -- the sender had spent them meanwhile. This move stands
    /// whatever the balance: a book may stand below nothing, the truth of a debt, the sum of every book keeps the coins there were,
    /// and no move of the hand leaves a book below what it holds (move).
    func retake(_ coins: Int, to peer: String, ref: String) -> Bool {
        let e = MTCoinEntry(k: .send, c: coins, ref: ref, peer: peer, on: nil, at: MTTimeChain.now())
        guard 0 < coins, !ref.isEmpty, !taken.contains(e.id), take(e) else { return false }
        keep([e], now: true)
        MontanaTrace.mark("coin_retake", "coins=\(coins) balance=\(balance)")
        return true
    }

    @discardableResult func receive(_ coins: Int, from peer: String, ref: String, on target: String?) -> Bool {
        guard MTCoinBook.fits(coins, beside: balance), !ref.isEmpty, !taken.contains("receive:" + ref) else {
            MontanaTrace.mark("coin_rx", "skipped coins=\(coins) known=\(taken.contains("receive:" + ref) ? 1 : 0)")
            return false
        }
        let e = MTCoinEntry(k: .receive, c: coins, ref: ref, peer: peer, on: target, at: Self.moment(ref))
        guard take(e) else { return false }
        keep([e], now: true)
        MontanaTrace.mark("coin_rx", "coins=\(coins) on=\(target == nil ? 0 : 1) balance=\(balance)")
        return true
    }

    /// A SEND THE CHAIN HOLDS STANDS IN THE BOOK WHATEVER ITS BALANCE (fold-7): the chain weighed the sum a moment before
    /// (MTCoinTx.send3), and the book, which mints nothing after the time cut (priced), holds less than the chain -- its refusal
    /// would keep coins the chain lets go. A book below nothing is the truth of what it no longer mints (retake).
    func sendHeld(_ coins: Int, to peer: String, ref: String, on target: String?) -> Bool {
        move(.send, coins, peer: peer, ref: ref, on: target, held: true)
    }

    private func move(_ k: MTCoinEntry.Kind, _ coins: Int, peer: String, ref: String, on: String?, held: Bool = false) -> Bool {
        let e = MTCoinEntry(k: k, c: coins, ref: ref, peer: peer, on: on, at: Self.moment(ref))
        // THE REFUSAL IS THE BOOK'S (the author's word 03.10 13:40): no move leaves more coins than the balance holds -- but a move
        // the chain already weighed (sendHeld).
        guard 0 < coins, !ref.isEmpty, !taken.contains(e.id), held || coins <= balance else {
            MontanaTrace.mark("coin_refused", "\(k.rawValue) coins=\(coins) balance=\(balance)")
            return false
        }
        guard take(e) else { return false }
        keep([e], now: true)
        MontanaTrace.mark("coin_\(k.rawValue)", "coins=\(coins) on=\(on == nil ? 0 : 1) balance=\(balance)")
        return true
    }

    /// A COIN LETTER STANDS AT ITS OWN BIRTH IN EVERY BOOK (the author's word 06.10.2026 08:2x UTC: «the sender and the receivers above
    /// all»): its name carries the millisecond the sender's phone gave it (ChatStore.mintMid), so the sender's transfer and the
    /// receiver's credit stand at that one millisecond -- as a letter's coin does (earn) -- not at two clocks' readings of two moments.
    /// Every other move stands at the millisecond it is made.
    private static func moment(_ ref: String) -> Double {
        (ref.hasPrefix("mid:t") ? ChatStore.birthMs(fromMid: ref) : nil) ?? MTTimeChain.now()
    }

    func coins(on target: String) -> Int { onTarget[target] ?? 0 }
    /// Whether the book holds a coin letter's credit by the letter's wire name (MTCoinSend.settle).
    func received(_ ref: String) -> Bool { taken.contains("receive:" + ref) }
    /// Whether the book holds a move of this kind under this name (MTCoinSend.hold counts a coin letter's moves by them).
    func holds(_ k: MTCoinEntry.Kind, _ ref: String) -> Bool { taken.contains(k.rawValue + ":" + ref) }
    /// One move by its kind and name (a coin letter's transfer, read when its row is gone: MTCoinSend.arrived, returnUndeliverable).
    func entry(_ k: MTCoinEntry.Kind, _ ref: String) -> MTCoinEntry? {
        let id = k.rawValue + ":" + ref
        return entries.last { e in e.id == id }
    }
}

/// A COIN LETTER (the author's word 03.10 13:52: «send coins to a contact in the chat as a coin-transfer bubble»): coins
/// sent to a person ride the chat's own letter road, as the chess letters do -- the coin and the number on the first line,
/// the machine line under it. A build that does not know it reads the words; this one draws the coin's bubble, and the
/// receiver's book credits it once by the letter's wire name (the same on both phones).
struct MTCoinLetter: Codable, Hashable {
    static let link = "montana://coin/1/"   // NOT-UI: the letter's machine line
    /// The text the transfer's one door is sending now (MTCoinSend.transfer): ChatStore.send lets no other coin letter leave.
    static var born: String?
    var c: Int
    var id: String
    /// THE LETTER NAMES ITSELF (the author's words 06.10.2026 09:3x-09:4x UTC: «close the double spends»; «the safety of the restore by the seed»): its id is the UUID of its own
    /// wire name, so a copy carried under another name -- pasted from a bubble, shared in, typed -- names a letter that is not
    /// itself (MTCoinSend.credits).
    func bound(to mid: String) -> Bool {
        let core = mid.hasPrefix("mid:") ? mid.dropFirst(4) : Substring(mid)
        guard let dash = core.firstIndex(of: "-") else { return false }
        return core[core.index(after: dash)...].caseInsensitiveCompare(id) == .orderedSame
    }
    func text() -> String? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        let code = data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
        return "🪙 " + String(c) + "\n" + Self.link + code   // NOT-UI: the coin glyph and a number, the same in every language
    }
    static func parse(_ text: String) -> MTCoinLetter? {
        guard text.hasPrefix("🪙 "), text.utf8.count <= 512,
              let line = text.split(separator: "\n", omittingEmptySubsequences: false).last, line.hasPrefix(link) else { return nil }
        let code = line.dropFirst(link.count).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        guard let data = Data(base64Encoded: code), let letter = try? JSONDecoder().decode(Self.self, from: data),
              0 < letter.c, UUID(uuidString: letter.id) != nil else { return nil }
        return letter
    }
}

extension Message {
    /// The coin letter this row is, when it is one in its own right (a forward or a reply quoting one pays nothing).
    var coinLetter: MTCoinLetter? {
        // An edited row is never a coin letter: its coins were taken once, under the words it was born with (06.10).
        guard !isForwarded, !edited, replyText == nil, imageFile == nil, videoFile == nil, audioFile == nil, docFile == nil else { return nil }
        return MTCoinLetter.parse(text)
    }
}

/// A PAIR WHOSE OTHER END HOLDS MY WORDS PAYS NOTHING (the author's words 06.10.2026 08:1x-08:2x UTC: «from the tablet I sent more than
/// 700 thousand to the iPhone 17, and in the end they were debited from her, not credited»; «check that the TimeChain does not allow
/// this»). The iPad (iPad12,1) and the iPhone 17 hold the same 24 words -- one book -- and the three coin letters between them took the
/// coins out of that book and laid them back: the receiver took the sender's debit by the seed's lane before the letter's credit
/// (762 000 at 08:14:21Z, the balance 134 until the letter landed at 08:19:13Z), and the sender took the receiver's credit by the vault
/// and sent again. A coin moved to one's own words is no move; it is refused at its birth -- the transfer, the paid reaction, the
/// bubble's coin, the call's seconds (MTCoinSend.canPay). Two witnesses say a pair is mine: the book (MTLocalCoinLedger.own) and the
/// pair's word about itself, carrying a tag only the same words make (MTCoinVault.ownTag). A coin letter of an older build still
/// lands and is credited: the book holds both ends to stand whole.
enum MTOwnWords {
    private static func key(_ conv: String) -> String { "ownWords." + conv }   // NOT-UI: the mark's key
    /// The tag my word about myself carries to this pair; nil while no words stand on the phone.
    static func tag(for conv: String) -> String? {
        guard !conv.isEmpty, let m = MontanaSeed.mnemonic, let e = MontanaSeedKeys.entropyFrom(mnemonic: m), e.count == 32 else { return nil }
        return MTCoinVault.ownTag(entropy: e, conv: conv).base64EncodedString()
    }
    /// The pair's word told its tag: the pair is mine when my words make the same one; a tag of other words lets the mark go.
    static func heard(_ tag: String, from conv: String) {
        guard !conv.isEmpty, let t = Data(base64Encoded: tag), t.count == 32, let m = MontanaSeed.mnemonic,
              let e = MontanaSeedKeys.entropyFrom(mnemonic: m), e.count == 32 else { return }
        let mine = MTCoinVault.ownTagHolds(t, entropy: e, conv: conv)
        guard UserDefaults.standard.bool(forKey: key(conv)) != mine else { return }
        if mine { UserDefaults.standard.set(true, forKey: key(conv)) } else { UserDefaults.standard.removeObject(forKey: key(conv)) }
        MontanaTrace.mark("own_words", "pair=\(String(conv.prefix(10))) mine=\(mine ? 1 : 0) by=word")
    }
    /// Whether the other end of this pair holds my words: by the book or by the pair's word.
    @MainActor static func mine(_ conv: String) -> Bool {
        !conv.isEmpty && (UserDefaults.standard.bool(forKey: key(conv)) || MTLocalCoinLedger.shared.whole.ownPeers.contains(conv))
    }
}

/// THE COINS LEAVE BY THE CHAT'S OWN ROADS (the author's words 03.10 13:40 and 13:52): a transfer is a letter of the pair,
/// a paid reaction is a reaction word that carries its coins. Both ask the book first: a short balance refuses here and
/// nothing leaves.
enum MTCoinSend {
    /// A field transfer has three honest outcomes. Only the available the page shows (MTCoinSplit.available) may call it short;
    /// an unanswered node record is pending, not an insufficient balance and not a second send.
    typealias TransferResult = MTCoinTransfer   // what a coin from the field came to, as the chat reads it (slice S2b b7d)
    /// The system chain's name for a restored credit: this prefix and the coin letter's wire name.
    static let restorePrefix = "restore:"
    /// A pair's own conversation, open to letters, of other words than mine: where a bubble burns its coin (pay).
    @MainActor static func pairOpen(_ chat: Chat, store: ChatStore) -> Bool {
        let conv = chat.convId ?? chat.name
        return !chat.isGroup && !ChatStore.isLocalRoom(chat.name) && chat.convId != nil && MontanaConv.holds(conv)
            && !store.refuses(conv) && !store.closedChats.contains(conv) && !MTOwnWords.mine(conv)
    }
    /// WHERE COINS CAN GO: EVERY OPEN PAIR, FOR A PERSON IS THEIR SEED AND THE WALLET IS IN IT (the author's words 11.10.2026 16:5x
    /// UTC: «why does it say Andrey has no wallet and not let me send -- he has a seed, so he has a wallet»; «a gross error -- the seed
    /// is already there, what has a wallet to do with it -- the person is the seed and everything is in it»). A pair had to say it held
    /// coins before it could take them, and on T1 24 of 29 pairs stood dimmed «no wallet yet» (coin_send_page pairs=29 holders=5,
    /// 11.10 15:40Z) -- people on builds with coins who had not yet sent the word that carried the mark. The coins are the seed's:
    /// a letter its build credits at the landing, or at the first launch of a build with coins (settle), and a letter not delivered
    /// in a day gives them back (hold).
    @MainActor static func canPay(_ chat: Chat, store: ChatStore) -> Bool {
        pairOpen(chat, store: store)
    }
    /// COINS TO A PERSON ARE A RECORD ON THE NODES, THE LETTER ONLY TELLS (MTCoinTx, Audit/COIN-TX-V1.md): the record's first node
    /// 200 is the moment they left and the book's debit; then a letter in the chat says how many and carries the confirmation link.
    /// False -- refused (the balance, the chat) or no node took the record: nothing moved.
    @MainActor static func transfer(_ coins: Int, to chat: Chat, store: ChatStore) async -> Bool {
        if case .sent(_) = await transferResult(coins, to: chat, store: store) { return true }
        return false
    }
    /// The same transfer with its record's name: one's own other account lands it at once (MTCoinTx.landOwn).
    @MainActor static func transferId(_ coins: Int, to chat: Chat, store: ChatStore) async -> String? {
        if case let .sent(id) = await transferResult(coins, to: chat, store: store) { return id }
        return nil
    }
    @MainActor static func transferResult(_ coins: Int, to chat: Chat, store: ChatStore) async -> TransferResult {
        let conv = chat.convId ?? chat.name
        let balance = MTCoinBook.ledger.balance
        let available = MTCoinSplit.shared.available   // the number every transfer page shows weighs the sum (16.10.2026 No.72)
        guard canPay(chat, store: store), 0 < coins else {
            MontanaTrace.mark("coin_refused", "transfer invalid coins=\(coins) balance=\(balance) own=\(MTOwnWords.mine(conv) ? 1 : 0)")
            return .refused
        }
        guard coins <= available else {
            MontanaTrace.mark("coin_refused", "transfer coins=\(coins) available=\(available) balance=\(balance) own=\(MTOwnWords.mine(conv) ? 1 : 0)")
            return .short
        }
        var result = await MTCoinTx.sendResult(coins, conv: conv)
        if case .noKey = result {
            // THE KEY IS ASKED, AND THE SAME SEND GOES WHEN IT COMES (the author's word 21.10.2026 09:41 UTC: «if there is a chat
            // there is everything -- the tunnel, the key -- and it must work at once and instantly»): nothing left the book, the
            // correspondent's phone answers the ask with its key (the about word's «q»), a live one within seconds -- T1's diary
            // 09:39:18Z, Petros's receipts in 4 s.
            E2E.shared.sendAboutIfNeeded(to: chat.name, askKey: true)
            var waited = 0
            while MTCoinTx.peerFrom(conv) == nil, waited < 40 {
                waited += 1
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
            MontanaTrace.mark("coin_v3", "key asked got=\(MTCoinTx.peerFrom(conv) == nil ? 0 : 1) waited_ms=\(waited * 250)")
            if MTCoinTx.peerFrom(conv) != nil { result = await MTCoinTx.sendResult(coins, conv: conv) }
        }
        switch result {
        case .sent(let id):
            // USER-DATA: the coin glyph, the number of coins and the time they are (the author's word 19.10.2026 14:44 UTC: «1 Coin
            // = 0.000000001 TCM = 1 second; in transfers both the time and the coins» -- coins, never TCM), the time in the sender's
            // language as the words of the letter are; the link is the transfer's own address
            let text = "🪙 " + MTCoinText.count(coins) + " · " + MTCoinText.time(coins) + "\n" + MTCoinTx.link + id
            _ = store.send(text: text, chat: chat.name, convRef: conv, silent: false, noLinkCard: true)
            return .sent(id)
        case .pending:
            MontanaTrace.mark("coin_pending", "transfer coins=\(coins) balance=\(balance)")
            return .pending
        case .refused:
            // NOTHING LEFT, AND THE PERSON IS TOLD SO (the author's word 20.10.2026 19:0x UTC: «on T1 it does not let me send a
            // transfer, it says it is being confirmed /// fix it -- everything must work at once and instantly»): every refused road
            // of send and send3 either never debited the book or
            // gave the coins back before it answered, so «being confirmed» over a refusal was a false gauge. The book already proved
            // the sum, so it is never shown as a shortage either.
            MontanaTrace.mark("coin_refused", "transfer not sent coins=\(coins) balance=\(balance)")
            return .refused
        case .noKey:
            MontanaTrace.mark("coin_refused", "transfer no receiver key coins=\(coins) balance=\(balance)")
            return .noKey
        case .paced:
            MontanaTrace.mark("coin_refused", "transfer paced: the key's node took its thirty records a minute twice over coins=\(coins) balance=\(balance)")
            return .paced
        }
    }
    /// COINS GIVEN ON THE CORRESPONDENT'S LETTER ARE A SEND OF THE CHAIN (the author's words 23.10.2026 00:27 and 00:37 UTC: the
    /// reactions «each a SEND record in the chain, the phone only the chain's mirror»): the coins leave by the pair's version 3 SEND
    /// under the letter's name, and the reaction word only names that SEND («op»: «coin3», «tx») -- the reader's book takes the
    /// coins from the chain alone (MTCoinTx.receive3), never from the word. An older build reads an unknown op as nothing at all.
    @MainActor static func react(_ coins: Int, on m: Message, in chat: Chat, store: ChatStore) async -> Bool {
        guard !m.isMine, let sid = m.msgId, !sid.isEmpty, canPay(chat, store: store) else { return false }
        return await give(coins, on: sid, words: m.text, to: chat.convId ?? chat.name)
    }
    /// An auto-reaction's coins on a chosen person's letter (MTAutoReact): the paid reaction's own road, once a letter -- the name
    /// «auto:» and the letter's wire name is taken before the SEND goes (a builds-before payment stands in the book under it), so a
    /// letter brought twice pays once; a SEND that never went gives the name back.
    static let autoPrefix = "auto:"   // NOT-UI: the book's own name
    @MainActor static func autoGive(_ coins: Int, on m: Message, to conv: String) async -> Bool {
        guard let sid = m.msgId, !sid.isEmpty, !MTLocalCoinLedger.shared.whole.holds(.spend, autoPrefix + sid),
              MTCoinTx.once(autoPrefix + sid) else { return false }
        let paid = await give(coins, on: sid, words: m.text, to: conv)
        if !paid { MTCoinTx.release(autoPrefix + sid) }
        return paid
    }
    /// The one road of a paid reaction: the pair's SEND under the letter's name; the word names it, carries no coins of its own.
    /// A SEND still waiting for its node's word (pending) has left the book and says no name -- the reader's scan credits it.
    @MainActor private static func give(_ coins: Int, on sid: String, words: String, to conv: String) async -> Bool {
        // A REACTION KEEPS ROOM FOR A SEND (the critic of 14486): six of the key's thirty records a minute stay the person's own.
        guard MTCoinTx.reactionRoom else {
            MontanaTrace.mark("coin_refused", "reaction pace laid=\(MTCoinTx.laidThisMinute()) kept=\(MTCoinTx.keptForSends) coins=\(coins)")
            return false
        }
        switch await MTCoinTx.send3(coins, conv: conv, on: sid) {
        case .sent(let id):
            let obj: [String: Any] = ["sid": sid, "txt": words, "e": "🪙", "op": "coin3", "c": coins, "tx": id]   // NOT-UI: wire keys
            guard let json = try? JSONSerialization.data(withJSONObject: obj), let body = String(data: json, encoding: .utf8) else { return true }
            MontanaDeliveryEngine.shared.enqueue(to: conv, chat: conv, mid: UUID().uuidString, text: reactionMark + body, silent: true)
            return true
        case .pending:
            return true
        case .notApplicable(let why):
            MontanaTrace.mark("coin_refused", "reaction v3 why=\(why) coins=\(coins)")
            return false
        case .failed, .paced:
            return false
        }
    }
    /// THE BUBBLE BURNS ITS COIN (the author's words 04.10.2026 22:21-22:31 UTC: «every bubble -1 coin»; «any bubble in an ordinary
    /// chat with the feed at the bottom»; and 19:29-19:32 UTC: «in ordinary chats take away the coin under every message as a
    /// reaction; the burning in an ordinary chat at both players -- a simple burning without a transfer»; «1 coin»): a bubble of
    /// mine in a pair's ordinary chat -- the Money Flow off; there the letters mint -- burns one coin of my book by the bubble's
    /// name, and nothing goes to the correspondent: no reaction word, no coin under the bubble; their phone burns its own for their
    /// bubbles. It burns when the bubble takes its wire name -- at its landing in the feed, or a media bubble when it is named
    /// (setMediaMid) -- and once, by that name, whichever door hands it over twice; a bubble a build before paid to its reader
    /// burns nothing more. An empty balance burns nothing and the bubble goes all the same; a coin letter is a payment in its own
    /// right, a chess step is the board's, a row of the phone's own goes nowhere.
    static let bubblePrefix = "bubble:"
    /// A letter is fresh for a day from its birth: an auto-reaction pays only a letter born within it (MTAutoReact.landed).
    static let fresh: Double = 86_400
    /// The name a reaction word's coins are credited under on the reader's book: this prefix and the name the word carries.
    static let receivedPrefix = "rc:"   // NOT-UI: the book's own name
    /// A COIN LETTER THAT DID NOT GO GIVES ITS COINS BACK (the author's word 04.10.2026 22:40 UTC: «I sent Narine 60 000 coins from
    /// T1, the letter did not go and they were taken from me; while the retry mark hangs, return them to the sender's balance with
    /// the mark not delivered»): a coin letter of mine holds its coins exactly while it is not red. Red, they come back by one move
    /// (back) and the bubble says so; on its way again under the hand's retry, or proven delivered after all -- the carriage goes on
    /// behind the red and a late receipt turns it delivered -- they are taken again by one move (again). The book's own moves say
    /// which it holds: the transfer, the agains and the backs, each by its name, so a door that asks twice moves nothing twice.
    /// Every door of the ladder asks it after it moves a coin letter of mine (advance, restartSend), and the history's first
    /// reading asks it of every one (settle) -- a letter red before this build gives its coins back at the first launch.
    static let backPrefix = "back:"
    static let againPrefix = "again:"
    /// A COIN LETTER NOT DELIVERED IN A DAY GIVES ITS COINS BACK (the author's words 10.10.2026 20:3x UTC: «a rule common to every
    /// wallet: if it did not arrive in 24 hours -- it comes back»): T2's 727 639 coins to an account whose phone is gone rode 44 hours
    /// without a receipt and stayed taken, for a letter of mine rides to its receipt (MTRefusal) and only red gave coins back. The
    /// coins follow the letter's proof as well as its rung: delivered or read, they are the receiver's; on its way and born within
    /// the day, held; red, or on its way past the day, back. The letter rides on under its rung, and a receipt after the day takes
    /// them again by the same again move -- a coin never stands in two books.
    static let day: Double = 86_400
    @MainActor static func hold(_ m: Message, in key: String) {
        guard m.isFromMe, let coin = m.coinLetter, !m.mid.isEmpty else { return }
        let book = MTLocalCoinLedger.shared.whole
        guard book.holds(.send, m.mid) else { return }   // a transfer the book refused never took a coin
        let again = moves(book, .send, againPrefix + m.mid), back = moves(book, .receive, backPrefix + m.mid)
        let held = again == back, owed = owes(m, in: key)
        if held, !owed {
            giveBack(coin.c, letter: m.mid, count: back, to: key, why: m.deliveryStatus == .failed ? "red" : "day")
        } else if !held, owed {
            let took = book.retake(coin.c, to: key, ref: againPrefix + m.mid + ":" + String(again + 1))
            MontanaTrace.mark("coin_again", "coins=\(coin.c) took=\(took ? 1 : 0) status=\(m.deliveryStatus)")
        }
    }
    /// Whether a coin letter of mine holds its coins: proven delivered, or on its way and born within the day.
    @MainActor private static func owes(_ m: Message, in key: String) -> Bool {
        switch m.deliveryStatus {
        case .delivered, .read: return true
        case .failed: return false
        case .sending, .sent:
            guard let born = ChatStore.birthMs(fromMid: m.mid) else { return true }   // a name without its birth: held as before
            return Date().timeIntervalSince1970 - born < day
        }
    }
    /// The day ends while no rung moves: every beat of the queue's mirror
    /// (MontanaDeliveryEngine.reconcile) asks the coin letters of mine still on their way.
    @MainActor static func due(_ store: ChatStore) {
        for (chat, rows) in store.messages {
            for m in rows where m.isFromMe && (m.deliveryStatus == .sending || m.deliveryStatus == .sent) && m.coinLetter != nil {
                hold(m, in: chat)
            }
        }
    }
    /// THE LETTERS THE AUTHOR NAMED UNDELIVERABLE (the author's words 10.10.2026 20:2x-20:3x UTC: «there was a transfer from T2 to a
    /// dead account on Android, the coins were not received, they got stuck somewhere -- find them and return them to the sender»;
    /// «and return them to the sender now»): T2's coin letter of 08.10 18:18:19Z rode 44 hours without a receipt, no device of the
    /// account waking (woken=0), and the Montana build that took the coins out of the chats ended its row and its queue item
    /// (queue_mirror 10.10 14:05:46Z) -- no chat of any wallet holds it, and the day above cannot reach it. Its name stands here;
    /// the book that holds its transfer -- T2's words, in whichever wallet they open -- gives the coins back once, by the back move.
    static let undeliverable = ["mid:t1791483499406-5CA782B0-A754-4443-B673-0579412060C2"]   // NOT-UI: a letter's wire name
    @MainActor static func returnUndeliverable(_ book: MTLocalCoinLedger) {
        for name in undeliverable {
            guard let sent = book.entry(.send, name), let peer = sent.peer else { continue }
            let back = moves(book, .receive, backPrefix + name)
            guard moves(book, .send, againPrefix + name) == back else { continue }
            giveBack(sent.c, letter: name, count: back, to: peer, why: "named")
        }
    }
    /// How many moves of one kind a coin letter's name has drawn: name:1, name:2 ...
    @MainActor private static func moves(_ book: MTLocalCoinLedger, _ k: MTCoinEntry.Kind, _ name: String) -> Int {
        var n = 0
        while book.holds(k, name + ":" + String(n + 1)) { n += 1 }
        return n
    }
    /// The one back move of a coin letter: its coins come home under the letter's next back name, and the system chain says why.
    @MainActor private static func giveBack(_ c: Int, letter mid: String, count back: Int, to key: String, why: String) {
        let ref = backPrefix + mid + ":" + String(back + 1)
        guard MTLocalCoinLedger.shared.whole.receive(c, from: key, ref: ref, on: nil) else { return }
        MTTimeChain.note("system", kind: "back", coins: c, ref: ref)
        MontanaTrace.mark("coin_back", "coins=\(c) letter=\(why)")
    }
    /// A COIN LETTER OF MINE ON ITS WAY IS NOT DELETED (the author's word «fix all points in order» 05.10.2026 18:4x UTC, the coin
    /// audit's first point): a row deleted by the hand while it said «sending» or «sent» took its letter out of the queue and the
    /// node box (the queue's mirror law, cargoGone, clearChat) and left its coins taken -- the receiver never had them and the
    /// sender never got them back. Giving them back at the deletion would pay twice whenever the receiver had already opened the
    /// letter and its receipt was still on the road; so the letter keeps its row until its road ends: delivered (the coins are the
    /// receiver's) or red (they come back by hold). Every door of the hand asks this first (ChatStore.deleteLocally,
    /// deleteEverywhere, deleteChat) and the menu offers no deletion of it.
    @MainActor static func travels(_ m: Message) -> Bool {
        guard m.isFromMe, m.deliveryStatus == .sending || m.deliveryStatus == .sent, !m.mid.isEmpty, m.coinLetter != nil else { return false }
        let book = MTLocalCoinLedger.shared.whole
        return book.holds(.send, m.mid) && moves(book, .send, againPrefix + m.mid) == moves(book, .receive, backPrefix + m.mid)
    }
    /// The row leaves by a road the hand does not hold -- the correspondent erased the conversation for both, and its queue and
    /// node box go with it (clearChat): a coin letter of mine not proven delivered and still holding its coins gives them back by
    /// the back move before the row goes.
    @MainActor static func release(_ m: Message, in key: String) {
        guard m.isFromMe, m.deliveryStatus != .delivered, m.deliveryStatus != .read, !m.mid.isEmpty, let coin = m.coinLetter else { return }
        let book = MTLocalCoinLedger.shared.whole
        guard book.holds(.send, m.mid) else { return }
        let back = moves(book, .receive, backPrefix + m.mid)
        guard moves(book, .send, againPrefix + m.mid) == back else { return }
        giveBack(coin.c, letter: m.mid, count: back, to: key, why: "gone")
    }
    /// A receipt for a coin letter of mine whose row is gone (released above, or red and then deleted): the letter did arrive, so
    /// the coins that came back are taken again by one move -- the same again a living row takes (hold) -- by the amount the
    /// book's own transfer named.
    @MainActor static func arrived(_ mid: String, from key: String) {
        let name = mid.hasPrefix("mid:") ? mid : "mid:" + mid
        let book = MTLocalCoinLedger.shared.whole
        guard book.holds(.send, name), let c = book.entry(.send, name)?.c else { return }
        let again = moves(book, .send, againPrefix + name), back = moves(book, .receive, backPrefix + name)
        guard again < back else { return }
        let took = book.retake(c, to: key, ref: againPrefix + name + ":" + String(again + 1))
        MontanaTrace.mark("coin_again", "coins=\(c) took=\(took ? 1 : 0) row=gone")
    }
    /// The hand's retry of a coin letter whose coins came back takes them again first: a short balance refuses the retry.
    @MainActor static func mayRetry(_ m: Message) -> Bool {
        guard m.isFromMe, let coin = m.coinLetter else { return true }
        let book = MTLocalCoinLedger.shared.whole
        guard book.holds(.send, m.mid) else { return true }
        return moves(book, .send, againPrefix + m.mid) == moves(book, .receive, backPrefix + m.mid) || coin.c <= book.balance
    }
    /// A COIN LETTER IS CREDITED WHEN IT NAMES ITSELF (the author's words 06.10.2026 09:3x-09:4x UTC: «close the double spends»; «the safety of the restore by the seed»): the
    /// first letter of a pair that names itself (MTCoinLetter.bound) notes its birth; from then on a letter of that pair born later
    /// under another name is a copy -- pasted, shared in, typed -- and credits nothing. A letter born before it, of a build that named
    /// none of its letters, stands as such letters always did.
    @MainActor static func credits(_ coin: MTCoinLetter, mid: String, from chat: String) -> Bool {
        let born = ChatStore.birthMs(fromMid: mid) ?? Date().timeIntervalSince1970
        let since = UserDefaults.standard.double(forKey: "coinBinds." + chat)   // 0: the pair never named a letter
        if coin.bound(to: mid) {
            if since == 0 || born < since { UserDefaults.standard.set(born, forKey: "coinBinds." + chat) }
            return true
        }
        guard since == 0 || born < since else {
            MontanaTrace.mark("coin_refused", "a copy under another name from=\(String(chat.prefix(10)))")
            return false
        }
        return true
    }
    /// A reaction word that carried coins arrived: credited once by the name it carries.
    @MainActor static func reacted(_ c: Int, ref: String, on sid: String, from chat: String) {
        guard 0 < c, !ref.isEmpty, !sid.isEmpty else { return }
        MTCoinBook.ledger.receive(c, from: chat, ref: receivedPrefix + ref, on: sid)
    }
    /// THE BOOK HOLDS EVERY COIN LETTER THE CHATS HOLD (the author's word 04.10.2026 20:57 UTC: «close it by construction»): once the
    /// history stands, a correspondent's coin letter the book never credited is credited now by its wire name -- the 123 000 coins
    /// the iPhone 15 Pro Max lost with an ended process come back at its next launch; a letter credited before is passed by its name.
    @MainActor static func settle(_ store: ChatStore) {
        let book = MTLocalCoinLedger.shared.whole
        var letters = 0, coins = 0
        for (chat, rows) in store.messages {
            for m in rows where !m.isFromMe {
                // ONE LETTER, ONE NAME, ONE CREDIT (09.10, MTCoinEntry.restoredName): a letter is credited under its wire name alone.
                // A copy a correspondent gave back carries that name inside its own (MTRestoredMid.given), so it is credited under it
                // -- the letter and its copy credit once, and a letter the vault had not heard of before the phone was lost comes
                // back; an archive's copy names no wire name and credits nothing -- its coins moved under the wire name.
                let wire = m.mid.hasPrefix(MTRestoredMid.given) ? String(m.mid.dropFirst(MTRestoredMid.given.count)) : m.mid
                guard MTChatMint.wireName(wire), !book.received(wire) else { continue }
                guard let coin = m.coinLetter, !MTGroup.isKey(chat), credits(coin, mid: wire, from: chat),
                      book.receive(coin.c, from: chat, ref: wire, on: nil) else { continue }
                // THE SYSTEM'S OWN BRANCH OF THE TIMECHAIN (the author's word 04.10.2026 21:22 UTC: «repair it by a system branch in the
                // TimeChain, as the diary»): the credit stands in the received chain as any other, and the system chain says why --
                // a coin letter the book had lost, restored by its wire name, its coins and its moment.
                MTTimeChain.note("system", kind: "restore", coins: coin.c, ref: MTCoinSend.restorePrefix + wire)
                letters += 1; coins += coin.c
            }
        }
        // A COIN LETTER OF MINE HOLDS ITS COINS WHILE IT IS NOT RED (hold), asked of every one as the history stands.
        for (chat, rows) in store.messages { for m in rows where m.isFromMe && m.coinLetter != nil { hold(m, in: chat) } }
        if 0 < letters { MTTimeChain.flush() }
        MontanaTrace.mark("coin_settle", "letters=\(letters) coins=\(coins) balance=\(book.balance)")
    }
}

/// AUTO-REACTIONS OF CHOSEN PEOPLE (the author's word 06.10.2026 14:3x UTC: «in the Money Flow's settings, on a long press, open a
/// page where I choose whom and how much I want to auto-react to, from my contacts»): a person chosen with a number of coins is paid
/// that many on every letter of theirs born after the choice, within a day of its birth, by the paid reaction's own road
/// (MTCoinSend.autoGive) -- once a letter, whichever door brings it. A short balance pays nothing and the letter stands as any other.
enum MTAutoReact {
    static let prefix = "autoReact."   // NOT-UI: a conversation's own rule (SeedScope.dataPrefixes)
    struct Rule { let coins: Int; let since: Double }
    static func rule(_ conv: String) -> Rule? {
        guard let d = UserDefaults.standard.dictionary(forKey: prefix + conv), let c = d["c"] as? Int, 0 < c,   // NOT-UI: the rule's keys
              let s = d["s"] as? Double else { return nil }   // NOT-UI: the rule's keys
        return Rule(coins: c, since: s)
    }
    /// The coins a person's every new letter is paid; nought lets the person go. The moment of the first choice stays while the
    /// number changes, so a letter between two edits is paid by the rule that stood.
    static func set(_ conv: String, coins: Int) {
        guard 0 < coins else { UserDefaults.standard.removeObject(forKey: prefix + conv); return }
        let since = rule(conv)?.since ?? Date().timeIntervalSince1970
        UserDefaults.standard.set(["c": coins, "s": since], forKey: prefix + conv)   // NOT-UI: the rule's keys
    }
    /// A letter of the pair landed (ChatStore, beside a coin letter's credit): a chosen person's fresh letter is paid.
    @MainActor static func landed(_ m: Message, in chat: String, store: ChatStore) {
        guard !m.isFromMe, let r = rule(chat), m.coinLetter == nil, m.gameLetter == nil, !MTRowLetter.ownRow(m.text),
              let born = ChatStore.birthMs(fromMid: m.mid), r.since <= born, Date().timeIntervalSince1970 - born <= MTCoinSend.fresh,
              let c = store.listChats().first(where: { c in c.name == chat }), MTCoinSend.canPay(c, store: store) else { return }
        let conv = c.convId ?? c.name
        Task { @MainActor in
            let paid = await MTCoinSend.autoGive(r.coins, on: m, to: conv)
            if paid { MTCoinPaid.shared.paid(r.coins, in: chat) }
            MontanaTrace.mark("auto_react", "coins=\(r.coins) paid=\(paid ? 1 : 0)")
        }
    }
}

/// THE COINS I PAID, SEEN IN THE CHAT (the author's word 04.10.2026 22:24 UTC: «in the chat the same way, an animation of a red
/// minus coin»): the one owner of the payment's sign -- what the book just burned from me for a bubble or paid for a call, and in which chat;
/// that chat shows it (MTPayPop).
@MainActor final class MTCoinPaid: ObservableObject {
    static let shared = MTCoinPaid()
    @Published private(set) var tick = 0
    private(set) var coins = 0
    private(set) var chat = ""
    func paid(_ c: Int, in key: String) {
        coins = c
        chat = key
        tick += 1
        MontanaTrace.markFolded("coin_paid", "coins=\(c)", window: 60)
    }
}

// COIN-RULES BEGIN -- tools/mt-coin-rules-check.py compiles this region as it stands with tools/coin-rules-tests.swift (COIN-TX-V3
// section 9: the vectors V1, V2, V3, V6 and the fold's steps); it reads nothing but Foundation and CryptoKit.
/// THE RULES OF A KEY'S CHAIN, ONE PLACE ON THE PHONE (Audit/COIN-TX-V3.md sections 1, 3 and 4): the fields a kind uses, the time a key
/// may mint, the blind and the receiver's commitment, and one record folded onto its key's state -- the rules the chain's node folds by
/// (montana-node-store.py _tx_step) and the Explorer (foldChain), each reading the one document on its own. The phone's sends, its
/// receipts and its copy of the chains ask them here.
enum MTCoinChainRules {
    static let v2Cut: Int64 = 1_792_443_600       // NOT-UI: 19.10.2026 21:00 UTC, the node's TX_V2_CUT (COIN-TX-V3 section 8)
    static let coinEpoch: Int64 = 1_788_210_000   // NOT-UI: 31.08.2026 21:00 UTC, the node's TX_COIN_EPOCH (section 3)
    /// τ1, THE MINTING'S WINDOW (the author's word 12.10.2026 12:5x UTC: «once in τ1 -- 60 seconds must be the window of time»): the
    /// shortest interval a MINT covers (sections 3, 7) and how often the phone asks its chain to take what the book holds above it.
    static let window: Int64 = 60
    static let zero = String(repeating: "0", count: 64)
    enum Kind: UInt8 { case send = 1, recv = 2, mint = 3, refund = 4, genesis = 5, burn = 6 }
    /// A record as the rules read it; a record of the layouts before kinds is a send that names no receiver.
    struct Rec { let id: String; let version: UInt8; let kind: UInt8; let amount: Int64; let from: String; let to: Data; let ref: String; let a: UInt64; let b: UInt64 }
    /// A key's state folded over its chain (section 3).
    struct St: Equatable { var head = MTCoinChainRules.zero; var height = 0; var birth: Int64 = 0; var mintEnd: Int64 = 0; var proven: Int64 = 0; var declared: Int64 = 0; var v3 = false; var lastAt: Int64 = 0; var minted: Int64 = 0 }
    struct SendInfo { let from: String; let amount: Int64; let at: Int64; let to: Data; let dec: Int64 }
    /// A_2(x) of section 4, the doubling rule: what the seconds 1..x of a key's life could mint before the second's cut, and the bound
    /// of every GENESIS -- 2 x min(13, max(1, bit_length(s) - 1)) a second.
    nonisolated static func timeA(_ x: Int64) -> Int64 {
        var total: Int64 = 0, lo: Int64 = 1, k: Int64 = 0
        while 0 < x, lo <= x {
            let hi = min(x, 2 * lo - 1)
            total += (hi - lo + 1) * min(13, max(1, k))
            lo = 2 * lo; k += 1
        }
        return 2 * total
    }
    nonisolated static var genesisCap: Int64 { timeA(v2Cut - coinEpoch) }
    /// 1 SECOND -- 1 COIN (section 4; the constitution, article 11; the author's words 19.10.2026 12:3x UTC: «the ceiling, an invariant --
    /// nothing else can mint or speed it up»): from this node second a MINT is weighed by A(x) = x over the key's whole life less all
    /// it minted; one taken before stands by the doubling rule. The node's TX_SECOND_CUT, the same second as the v2 cut.
    nonisolated static let secondCut: Int64 = v2Cut
    /// What the seconds 1..x of a key's life may mint by a MINT its node takes at the second `at`: chosen by at, never by the interval.
    nonisolated static func allowTime(_ x: Int64, at: Int64) -> Int64 { secondCut <= at ? max(0, x) : timeA(x) }
    /// THE CHAIN MINTS THE KEY'S TIME ITSELF (section 4, fold-6; the author's words 21.10.2026 14:1x UTC: «only the core mints», «1 coin --
    /// 1 second, the client merely shows it»): from this node second every v3 record first folds the seconds its key has lived, so no
    /// phone lays a MINT for its time. The node's TX_TIME_CUT, 22.10.2026 21:00 UTC.
    nonisolated static let timeCut: Int64 = 1_792_702_800
    /// MINTING IS ITS OWN ROAD (fold-7; the author's words 23.10.2026 00:27 and 00:37 UTC: «minting is a separate entity, and it happens
    /// if the person is online or behind the VPN» -- «right, do it»): from this node second the key's life mints nothing by itself, and a
    /// MINT counts only what its interval holds of the last mintFresh seconds before its node took it -- the seconds the key was present.
    /// A BURN is taken from the same second. The node's TX_ONLINE_CUT, 25.10.2026 21:00 UTC.
    nonisolated static let onlineCut: Int64 = 1_792_962_000
    nonisolated static let mintFresh: Int64 = 120
    /// NO MINT AT ALL FROM THE STOP (fold-9; the author's decisions 373 and 377 «a», link 12047; the author's word 29.10.2026 19:31 UTC,
    /// link 11871): from this node second the node refuses every MINT (Stopped, code 18), so the phone lays none and shows no seconds
    /// on their way to one. The node's TX_MINT_STOP (mt-coin), 30.10.2026 12:00 UTC.
    nonisolated static let mintStop: Int64 = 1_793_361_600
    /// The key's seconds of life up to the node second `at`, and never past the online cut, credited once, proven by the same step.
    /// THE PAST NEVER EATS THE PRESENT (fold-8; the author's words 23.10.2026 19:1x and 19:21 UTC: «Andrey's coins are not credited --
    /// fix it in the new build»): a key that minted above its life before the cut by the doubling rule -- 28 of 96 keys on 23.10, every
    /// living phone's -- still gets every second since its last record, never before the cut, so its present seconds are not eaten by
    /// its past: the credit is the greater of its unminted life and those seconds.
    nonisolated static func timeStep(_ s: St, at: Int64) -> St {
        guard timeCut <= at, 0 < s.height else { return s }
        let end = min(at, onlineCut)
        let fresh = max(0, end - max(s.lastAt, timeCut, s.birth))
        let credit = max(end - s.birth - s.minted, fresh)
        guard 0 < credit else { return s }
        var n = s
        n.proven = s.proven + credit; n.minted = s.minted + credit
        return n
    }
    /// What the time step adds to a key folded at the node second `s` by the node second `t`, no record laid between: from the time cut
    /// both sides of its credit grow by one a second up to the online cut, so the node's later word is the earlier one plus these seconds.
    nonisolated static func since(_ s: Int64, to t: Int64) -> Int64 {
        guard timeCut <= s else { return 0 }
        return max(0, min(t, onlineCut) - min(s, onlineCut))
    }
    /// The seconds a MINT taken at the node second `at` may count from the online cut: what its interval holds of the last mintFresh,
    /// never a second before the cut -- the time step credited every one of those (fold-8).
    nonisolated static func present(t0: Int64, t1: Int64, at: Int64) -> Int64 { max(0, t1 - max(t0, at - mintFresh, onlineCut)) }
    /// A BOOK'S PAST, NEVER A FRESH KEY'S WORD (18.10.2026, the critic's P-1; the node's TX_GENESIS_GATE): from this node second a
    /// GENESIS above 0 stands only on the key's own past on its chain and announces at most the time since that past began.
    nonisolated static let genesisGate: Int64 = 1_792_354_500
    /// What a GENESIS of a key at the node second `at` may announce: the book's past, under the cap and the time since its birth.
    nonisolated static func genesisRoom(height: Int, birth: Int64, at: Int64) -> Int64 {
        if v2Cut <= at { return 0 }
        if at < genesisGate { return genesisCap }
        return height == 0 ? 0 : min(genesisCap, timeA(at - birth))
    }
    /// Section 1: a field its kind does not use is zero; a SEND names its commitment, a RECV and a REFUND the SEND they settle, and the
    /// announced part of a SEND or RECV (t0) is never above its amount -- as the node's reader holds them.
    nonisolated static func fieldsHold(kind: UInt8, amount: UInt64, pair: Data, to: Data, ref: Data, a: UInt64, b: UInt64) -> Bool {
        let none = Data(count: 32)
        switch Kind(rawValue: kind) {
        case .send?: return ref == none && b == 0 && to != none && a <= amount
        case .recv?: return pair == none && b == 0 && ref != none && a <= amount
        case .mint?: return pair == none && to == none && ref == none
        case .refund?: return pair == none && to == none && ref != none && a == 0 && b == 0
        case .genesis?: return pair == none && to == none && ref == none && a == 0 && b == 0
        case .burn?: return pair == none && to == none && ref == none && b == 0 && a <= amount
        case nil: return false
        }
    }
    /// The blind of a SEND: HMAC-SHA-256 under the pair's secret over ASCII mt-coin-blind and the SEND's nonce (section 1).
    nonisolated static func blind(secret: Data, nonce: Data) -> Data {
        Data(HMAC<SHA256>.authenticationCode(for: Data("mt-coin-blind".utf8) + nonce, using: SymmetricKey(data: secret)))
    }
    /// The receiver's commitment: SHA-256 of ASCII mt-coin-to, the receiver's from (32 bytes) and the blind (section 1).
    nonisolated static func commitment(from: Data, blind: Data) -> Data { Data(SHA256.hash(data: Data("mt-coin-to".utf8) + from + blind)) }
    nonisolated static func bytes(_ s: String) -> Data? {
        guard s.count % 2 == 0 else { return nil }
        var out = Data(); var i = s.startIndex
        while i < s.endIndex {
            let j = s.index(i, offsetBy: 2)
            guard let b = UInt8(s[i..<j], radix: 16) else { return nil }
            out.append(b); i = j
        }
        return out
    }
    /// A V2 RECORD THAT SPENT STANDS OPEN AS A SEND (section 5, fold-4; P-3 of Agent 95): on an opened chain it takes this declared
    /// part, and its sender's REFUND gives the same split back after its day -- it names no receiver, so no chain could ever take it.
    /// nil: a v2 record of the book's past (the chain not opened), which spent nothing, or one above the balance.
    nonisolated static func v2Spent(_ s: St, amount: Int64) -> Int64? {
        guard s.v3, amount <= s.proven + s.declared else { return nil }
        return max(0, amount - s.proven)
    }
    /// One record folded onto its key's state by the nodes' rules: the next state, or nil for a record that breaks a rule; wait for a
    /// RECV or REFUND whose SEND is not folded yet.
    nonisolated static func step(_ s: St, _ p: Rec, _ at: Int64, _ sends: [String: SendInfo], _ settled: Set<String>) -> (next: St?, wait: Bool) {
        // first the key's time, then the record's kind (section 3, fold-6); a refused record leaves the state as it stood
        let s = p.version == 3 ? timeStep(s, at: at) : s
        var n = s
        n.head = p.id; n.height += 1; n.lastAt = max(at, s.lastAt)
        if s.height == 0 { n.birth = at; n.mintEnd = at }
        let a = p.amount
        if p.version == 2 {
            // EVERY TRANSFER MOVES ITS BALANCE (section 3, fold-2; the author's words 12.10.2026 09:1x UTC: «all transfers must be
            // simply correct, not versions»): after the chain opened, a send that names no receiver spends as a SEND, proven first
            guard s.v3 else { return (n, false) }
            guard let d = v2Spent(s, amount: a) else { return (nil, false) }
            n.proven = s.proven - (a - d); n.declared = s.declared - d
            return (n, false)
        }
        n.v3 = true
        switch Kind(rawValue: p.kind) {
        case .genesis?:
            if s.v3 || (0 < a && v2Cut <= at) || genesisCap < a { return (nil, false) }
            if 0 < a && genesisGate <= at && (s.height == 0 || timeA(at - s.birth) < a) { return (nil, false) }
            n.declared = a
        case .mint?:
            let t0 = Int64(p.a), t1 = Int64(p.b)
            if s.height == 0 || t0 < s.mintEnd || t1 < t0 + 60 || at < t1 { return (nil, false) }
            // THE SUM OF TIME (section 4, fold-3): all the key's MINTs together stay under A(t1 - birth), so a MINT below its
            // interval's seconds leaves the key's time to the next one (17.10.2026, P1: a MINT of 120 laid before the pay for 4.4 days
            // away had closed those days, and 2 452 406 coins stood in the book and not on the chain); from the cut 1 coin a second
            // from the online cut the present seconds alone weigh it: the intervals never overlap, so the life's sum is not asked and a
            // key that minted above its life before the time cut mints its present seconds like any other (fold-8)
            if onlineCut <= at {
                if present(t0: t0, t1: t1, at: at) < a { return (nil, false) }
            } else if allowTime(t1 - s.birth, at: at) - s.minted < a { return (nil, false) }
            n.proven = s.proven + a; n.mintEnd = t1; n.minted = s.minted + a
        case .send?, .burn?:
            // a BURN spends as a SEND and names no one: no RECV or REFUND can name it (the open SENDs hold SENDs alone)
            if p.kind == Kind.burn.rawValue && at < onlineCut { return (nil, false) }
            let dec = Int64(p.a)
            if s.proven + s.declared < a || dec != max(0, a - s.proven) { return (nil, false) }
            n.proven = s.proven - (a - dec); n.declared = s.declared - dec
        case .recv?, .refund?:
            guard let S = sends[p.ref] else { return (nil, true) }
            if S.amount != a || settled.contains(p.ref) { return (nil, false) }
            if p.kind == Kind.recv.rawValue {
                guard let f = bytes(p.from), S.dec == Int64(p.a), commitment(from: f, blind: p.to) == S.to else { return (nil, false) }
            } else if S.from != p.from || at < S.at + 86_400 {
                return (nil, false)
            }
            n.proven = s.proven + a - S.dec; n.declared = s.declared + S.dec
        case nil:
            return (nil, false)
        }
        return (n, false)
    }
}
// COIN-RULES END

/// THE BALANCE AS ITS CHAIN HOLDS IT (COIN-TX-V3 section 3; the chairman's task 12.10.2026, No.65: «the balance figure stays one, and
/// beneath it the split proven / declared»): what the person's own chain proves by mints and receipts, and what its opening announced.
/// This phone's own copy of the chains says it when the person keeps one (MTCoinReplica, an independent fold); otherwise the chain's
/// node does (POST /tx-head), and a word of the node never stands over the copy's fresher one. Nothing before the chain opened.
@MainActor final class MTCoinSplit: ObservableObject {
    static let shared = MTCoinSplit()
    struct Split: Equatable { let proven: Int64; let declared: Int64; let fromCopy: Bool; let at: TimeInterval; let height: Int; let second: Int64; var mintEnd: Int64 = 0 }
    @Published private(set) var split: Split?
    /// THE NEWEST STATE OF THE CHAIN SPEAKS, WHOEVER FOLDED IT (the author's words 12.10.2026 12:5x UTC: «the available depends on the
    /// network and the confirmed ... everything at once»): the copy's fold stood an hour over every fresher word of the node, so a RECV or
    /// a MINT the node had taken waited for the copy's next round. The chain's height says which word is newer; one height is one state.
    func heard(proven: Int64, declared: Int64, opened: Bool, fromCopy: Bool, height: Int, second: Int64, mintEnd: Int64) {
        guard opened else { return }
        if let s = split, height < s.height { return }
        let now = Date().timeIntervalSince1970
        if split?.proven != proven || split?.declared != declared || split?.height != height || split?.mintEnd != mintEnd {
            split = Split(proven: proven, declared: declared, fromCopy: fromCopy, at: now, height: height, second: second, mintEnd: mintEnd)
            keep(coins: proven &+ declared, height: height)
        }
        if flying.contains(where: { _, f in f.height < height }) { flying = flying.filter { _, f in height <= f.height } }
        told()
        MontanaTrace.markFolded("coin_split", "proven=\(proven) declared=\(declared) copy=\(fromCopy ? 1 : 0)", window: 600)
    }
    /// THE CHAIN'S LAST WORD OUTLIVES THE RUN (the author's word 29.10.2026 09:28 UTC, link 11329: «1.5 million coins were written
    /// off and the balance was 7.9 million, now it is less -- this is not admissible»): Andrey's phone 13498CA8 opened the wallet at
    /// 06:55 UTC on LTE, its road to the chain's node failed (coin_replica code=-1, handshake_timeout), and the page showed the book,
    /// 6 567 126, while the chain held 7 900 616 with no record after the MINT of 27.10 -- a debit the chain never had. The last state
    /// the chain told for the seated key stands in the person's folder (MTCoinPlace, moved with the seat) and speaks until the chain
    /// speaks in this run; the book only before the chain ever spoke for this key. It spends nothing by itself: every send is weighed
    /// again by the chain's own word (send3), and no other road sends after the v2 cut (sendResult).
    private struct LastWord: Codable { let key: String; let coins: Int64; let height: Int; let at: TimeInterval }
    private static let lastName = "chain-last-word.json"   // NOT-UI: the file's name in the person's folder
    private var last: (generation: Int, word: LastWord?)?
    private var lastWord: LastWord? {
        let g = MTCoinBook.generation
        if let l = last, l.generation == g { return l.word }
        var word: LastWord?
        if let u = MTCoinPlace.file(Self.lastName), let d = try? Data(contentsOf: u),
           let w = try? JSONDecoder().decode(LastWord.self, from: d), w.key == MTCoinTx.myKeyTag { word = w }
        last = (g, word)
        return word
    }
    /// Whether the chain ever spoke for the seated key -- in this run or in one before it.
    var spoke: Bool { split != nil || lastWord != nil }
    private func keep(coins: Int64, height: Int) {
        guard let key = MTCoinTx.myKeyTag, let u = MTCoinPlace.file(Self.lastName) else { return }
        let w = LastWord(key: key, coins: coins, height: height, at: Date().timeIntervalSince1970)
        guard let d = try? JSONEncoder().encode(w) else { return }
        MTDiskDoor.write(d, to: u, "coin-last", options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        last = (MTCoinBook.generation, w)
    }
    /// THE SENDS ON THEIR WAY TO THE CHAIN (fold-7; the author's words 23.10.2026 00:27 UTC: «the phone only mirrors the chain»): a SEND
    /// laid on the head of height h stands in every state of a height above h, or never will -- another record took its place on that
    /// head. Until the chain tells a state above h, its coins are on their way and the available leaves them out. Held in memory: a new
    /// run reads the chain after the send's road has ended.
    @Published private var flying: [String: (height: Int, coins: Int64)] = [:]
    func laid(_ id: String, coins: Int, on height: Int) {
        flying[id] = (height, Int64(coins))
        told()
    }
    /// THE AVAILABLE, ONE NUMBER EVERYWHERE (the author's word 16.10.2026 14:19 UTC: «on the coins page do not show Proven, Declared,
    /// More wait to be minted below -- it is enough to show how much is available with one owner, so that a transfer from the chat
    /// and from any place shows only the available»): what the person's chain holds for its one owner, proven and declared, less the
    /// sends on their way to it; before the chain has spoken in this run, its last word (lastWord), and the book only when it never
    /// spoke for this key. The book no longer caps it (fold-7, the author's
    /// words 23.10.2026 00:37 UTC: «minting is a separate entity»): the book mints nothing after the time cut (MTLocalCoinLedger.priced),
    /// so as a ceiling it would freeze the number while the chain mints. The wallet, the chat's coin plate, the send page, the chess
    /// stake and the word about oneself show it, and a transfer is weighed by it (MTCoinSend.transferResult).
    var available: Int {
        guard let s = split else { return lastWord.map { w in Int(clamping: max(0, w.coins)) } ?? MTLocalCoinLedger.shared.balance }
        let away = flying.values.reduce(Int64(0)) { sum, f in s.height <= f.height ? sum &+ f.coins : sum }
        let lived = MTCoinChainRules.since(s.second, to: s.second &+ Int64(max(0, Date().timeIntervalSince1970 - s.at)))
        return Int(clamping: max(0, s.proven &+ s.declared &+ lived &- away))
    }
    /// THE SECONDS ON THEIR WAY TO THE CHAIN (the author's words 26.10.2026 09:2x UTC, links 8615 and 8617: «I do not see how the
    /// coins are minted every second on the Time Coins page ... even if not all are available or finalized»; «let it count so, then
    /// show visually what happens before the window is finalized»): from the online cut the chain credits a person's seconds only by
    /// a MINT the phone lays while the person is here, once in a minute or so (MTCoinTx.reconcile), so the chain's number stood and
    /// leapt. These are the very seconds the next MINT will name -- from the later of the last MINT's end, the node's freshness less
    /// the road's margin and the person's coming -- counted at the node's second; when it lands the chain holds them and they leave
    /// here, so the sum moves on without a leap. Shown and never spent: the available leaves them out, and a transfer weighs nothing else.
    var minting: Int {
        guard let s = split, let from = MTCoinTx.hereFrom, MTCoinTx.here else { return 0 }
        let now = s.second &+ Int64(max(0, Date().timeIntervalSince1970 - s.at))
        guard MTCoinChainRules.onlineCut <= now, now < MTCoinChainRules.mintStop else { return 0 }
        let t0 = max(s.mintEnd, now - MTCoinChainRules.mintFresh + MTCoinTx.presentMargin, from)
        return Int(clamping: max(0, now - t0))
    }
    /// What the wallet's Time Balance shows: the available and the seconds on their way to it -- before the coin chain's stop the
    /// seconds a MINT would name, from it the seconds in the network the core has not confirmed yet (MTPresenceWait).
    var growing: Int { available + (split == nil ? 0 : minting) + MTPresenceWait.seconds }
    /// The number the readers off the main actor hear (MTCoinBalance): the available, told at every move of the book and the chain.
    /// Before the chain has spoken the available is the book's, so its views hear every move of the book here.
    private var shown: Int?
    func told() {
        if split == nil { objectWillChange.send() }
        shown = growing
        MTCoinBalance.set(available)
    }
    /// THE CHAIN'S SECOND ON THE SCREEN (the author's words 23.10.2026 20:2x UTC: «in the client the minting shows just as before, only
    /// it all happens at the core's level»): the chain credits the key every second by its own step (MTCoinChainRules.since), so the
    /// beat of the minting raises those seconds with their sum as the book's coins once rose, and never a coin the chain did not fold.
    /// The seconds on their way rise by the same beat (minting), and when they leave -- the person away, or the MINT landed -- the
    /// figure is told again without a rise.
    func beat() {
        guard spoke else { return }
        guard let before = shown else { shown = growing; objectWillChange.send(); return }
        let now = growing
        guard before != now else { return }
        objectWillChange.send()
        told()
        if before < now { MTCoinFlash.shared.born(now - before) }
    }
}

/// THE SECONDS IN THE NETWORK WAIT FOR THE CORE (the author's decision 443 = (b), link 13549, 30.10.2026 19:25 UTC: «the core confirms
/// after the window's finalization, and the balance shows the crediting every second, while the available changes only after the
/// core's confirmation by the fact of finalization»; «the stop of minting was about everything except in the network»; links 13528 and
/// 13531: build 2324 showed no crediting every second). From the coin chain's stop (MTCoinChainRules.mintStop) its nodes take no MINT,
/// so the seconds the person is here -- the app in front of them or the living tunnel (MTCoinTx.here) -- are counted on this phone and
/// rise in the Time Balance (MTCoinSplit.growing), never in the available, and nothing spends them: only the core makes coins of them.
/// Kept in the person's folder (MTCoinPlace), folded at every beat of presence, so a stay that ends or a run that dies loses at most
/// one beat, and a seat moved takes its own. The open stay lives in memory alone: a run killed never counts the time it was dead.
@MainActor enum MTPresenceWait {
    private struct Kept: Codable { let key: String; var seconds: Int64 }
    private static let name = "presence-waiting.json"   // NOT-UI: the file's name in the person's folder
    private static var kept: Kept?
    private static var from: (key: String, at: TimeInterval)?
    private static var watching = false
    /// The first second counted: before the stop a MINT named these seconds (MTCoinSplit.minting).
    nonisolated static let start = TimeInterval(MTCoinChainRules.mintStop)
    private static func load(_ key: String) -> Kept {
        if let k = kept, k.key == key { return k }
        var k = Kept(key: key, seconds: 0)
        if let u = MTCoinPlace.file(name), let d = try? Data(contentsOf: u),
           let w = try? JSONDecoder().decode(Kept.self, from: d), w.key == key { k = w }
        kept = k
        return k
    }
    private static func save(_ k: Kept) {
        kept = k
        guard let u = MTCoinPlace.file(name), let d = try? JSONEncoder().encode(k) else { return }
        MTDiskDoor.write(d, to: u, "coin-rules-kept", options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
    /// The seconds waiting for the core: the kept ones and the open stay's.
    static var seconds: Int {
        guard let key = MTCoinTx.myKeyTag else { return 0 }
        let open = from.map { f in f.key == key ? max(0, Date().timeIntervalSince1970 - f.at) : 0 } ?? 0
        return Int(clamping: load(key).seconds &+ Int64(open))
    }
    /// The person came: a stay opens, never before the stop.
    static func open() {
        watch()
        guard from == nil, let key = MTCoinTx.myKeyTag else { return }
        let now = Date().timeIntervalSince1970
        guard start <= now else { return }
        from = (key, now)
    }
    /// The open stay's seconds join the kept ones, and the stay goes on from now.
    static func fold() {
        guard let f = from else { return }
        let now = Date().timeIntervalSince1970
        var k = load(f.key)
        k.seconds &+= Int64(max(0, now - f.at))
        save(k)
        from = (f.key, now)
    }
    /// The person left: the stay's seconds are kept and it closes.
    static func close() {
        fold()
        from = nil
    }
    /// The app leaving the screen ends the stay at once unless the tunnel keeps the person here; the presence's beat would end it
    /// up to a beat later (MTCoinTx.presentBeat).
    private static func watch() {
        guard !watching else { return }
        watching = true
        for n in [UIApplication.didEnterBackgroundNotification, UIApplication.willTerminateNotification] {
            NotificationCenter.default.addObserver(forName: n, object: nil, queue: .main) { _ in
                Task { @MainActor in if !MTCoinTx.here { close() } }
            }
        }
    }
}

/// THE COIN TRANSFER IS ONE RECORD ON THE NODES (Audit/COIN-TX-V1.md; the author's words 11.10.2026 16:5x-17:2x UTC: «a person is
/// their seed and everything is in it»; «so I can pay them in any scenario»; «either the coins left or not -- there is no third»;
/// «professional, in the TimeChain, for auditors»). A coin letter carried the coins inside a letter, so their fate was the letter's:
/// a build that buries the coin link (2162-2179) dropped it and the coins stood a day nowhere (the critic 11.10, B-1). The record is
/// signed by the seed's coin key and laid on the nodes' append-only log; a node's 200 is the moment the coins left, and the
/// receiver's book finds the record by its pair's tag on any later build, on any device of its seed. A chat letter only tells.
enum MTCoinTx {
    static let size = 5330    // version 1 (Audit/COIN-TX-V1.md), read only: builds 2190 and older send it
    static let size2 = 5362   // version 2 (Audit/COIN-TX-V2.md), the record this build sends
    static let refPrefix = "tx:"          // NOT-UI: the book's name of a transfer's moves
    static let backPrefix = "txback:"     // NOT-UI: the book's name of a debit no node took
    static let link = "https://montana.xxx/explorer/#tx="   // NOT-UI: the transfer's confirmation link (the Explorer)
    static let explorer = URL(string: "https://montana.xxx/explorer/") ?? URL(fileURLWithPath: "/")   // NOT-UI: the Explorer's page
    static let keyLink = "https://montana.xxx/explorer/#key="   // NOT-UI: a coin key's whole chain in the Explorer
    /// THE CHAINS' NODES (Audit/COIN-TX-V2.md): the protocol's two nodes, sorted by name, each with its one door -- Moscow and
    /// Amsterdam; a key's chain lives on the one at the index of the key tag's first byte. Every phone and the Explorer read the same
    /// table, so a chain never splits; a node not in it (Lauterbourg keeps no transfers) is no chain node.
    static let chainNodes: [(name: String, host: String)] = [("montana.quest", "api.montana.quest"), ("montana.xxx", "montana.xxx")]   // NOT-UI: the protocol's chain set, one place
    private static let magic = Data("MTTX".utf8)
    private static let signed1 = Data("mt-coin-tx-v1".utf8)
    private static let signed2 = Data("mt-coin-tx-v2".utf8)

    static let zero = String(repeating: "0", count: 64)
    struct Record {
        let id: String; let version: UInt8; let coins: Int; let birthMs: UInt64; let pair: Data; let prev: String; let from: String; let bytes: Data
        var kind: UInt8 = 1; var to = Data(); var ref = ""; var a: UInt64 = 0; var b: UInt64 = 0; var nonce = Data()   // version 3's fields (COIN-TX-V3)
    }
    enum Word: Equatable { case left, notLeft, unknown, behind, paced }
    /// THE KEY'S PACE HAS ONE OWNER (the critic of 14486, 02.11.2026): the node takes thirty records a minute from one key (V3
    /// section 7, TX_KEY_PM), and the paid reactions -- a person's and the auto-reactions' -- spent the whole minute a send of the
    /// person's own then needed (T1 11:15:12 UTC, 429 «key pace»): two spenders of one budget and no keeper. Every record the node
    /// took from this phone stands here by its moment; a reaction leaves six of the thirty to the person's sends (reactionRoom),
    /// and a send that still meets the pace waits the minute out (send3).
    static let keyPace = 30, keptForSends = 6
    private static let paceLock = NSLock()
    private static var laidAt: [Date] = []   // under paceLock (LOCK-OK: one array, never held across a wait)
    static func laidThisMinute() -> Int {
        paceLock.lock(); defer { paceLock.unlock() }
        laidAt.removeAll { 60 <= Date().timeIntervalSince($0) }
        return laidAt.count
    }
    private static func tookOne() { paceLock.lock(); laidAt.append(Date()); paceLock.unlock() }
    static var reactionRoom: Bool { laidThisMinute() < keyPace - keptForSends }   // paced: the key's pace at its node (429 «key pace», V3 section 7): not laid, laid again when the minute frees

    private static let keyLock = NSLock()
    private static var keyCache: (words: Data, pk: Data, sk: Data)?
    /// The seed's coin key: HKDF-Expand(master_seed, "mt-coin-tx", 32) into ML-DSA-65 -- one on every device of the words, and no
    /// relation to the identity's account key (a coin key names no person's number or card).
    static func keys() -> (pk: Data, sk: Data)? {
        guard let words = MontanaSeed.mnemonic else { return nil }
        let tag = Data(SHA256.hash(data: Data(words.utf8)))
        keyLock.lock()
        if let c = keyCache, c.words == tag { keyLock.unlock(); return (c.pk, c.sk) }
        keyLock.unlock()
        guard let h = MontanaSeed.root.flatMap(hands) else { return nil }   // the seated root's one owner (link 14170)
        keyLock.lock(); keyCache = (tag, h.pk, h.sk); keyLock.unlock()
        return (h.pk, h.sk)
    }
    /// One key's hands: the person seated (keys()) or a person on this phone's shelf (derive) -- the record is theirs, signed by them.
    struct Hands { let pk: Data; let sk: Data; var from: String { MTCoinTx.keyTag(pk) } }
    /// The coin key of any words this phone holds, derived anew (never cached: a shelf's words are asked rarely).
    static func derive(_ words: String) -> Hands? { MontanaQueueKeys.masterSeed(words).flatMap(hands) }
    /// The coin key's hands from a master seed: HKDF-Expand(master_seed, "mt-coin-tx", 32) into ML-DSA-65.
    private static func hands(_ master: Data) -> Hands? {
        guard master.count == 64 else { return nil }
        var seed = [UInt8](repeating: 0, count: 32)
        let role = Array("mt-coin-tx".utf8)
        let rc = master.withUnsafeBytes { m -> Int32 in
            role.withUnsafeBufferPointer { r -> Int32 in
                guard let mb = m.bindMemory(to: UInt8.self).baseAddress else { return -1 }
                return mt_mldsa_seed_for_role(mb, r.baseAddress, role.count, &seed)
            }
        }
        guard rc == 0 else { return nil }
        var pk = [UInt8](repeating: 0, count: 1952), sk = [UInt8](repeating: 0, count: 4032)
        guard mt_mldsa_keypair_from_seed(seed, &pk, &sk) == 0 else { return nil }
        return Hands(pk: Data(pk), sk: Data(sk))
    }
    static func hex(_ d: Data) -> String { d.map { b in String(format: "%02x", b) }.joined() }
    private static func unhex(_ s: String) -> Data? {
        guard s.count % 2 == 0 else { return nil }
        var out = Data(); var i = s.startIndex
        while i < s.endIndex {
            let j = s.index(i, offsetBy: 2)
            guard let b = UInt8(s[i..<j], radix: 16) else { return nil }
            out.append(b); i = j
        }
        return out
    }
    /// The coin key's tag on the wire: SHA-256 of the coin key -- the sender's name in every record.
    static func keyTag(_ pk: Data) -> String { hex(Data(SHA256.hash(data: pk))) }
    static var myKeyTag: String? { keys().map { k in keyTag(k.pk) } }
    /// The pair's tag: HMAC-SHA-256 under the pipe's secret over "mt-coin-pair-v1" -- its two ends know it, no one else does.
    /// Made at the pipe's birth by the secret's one owner (MTPipeKey.kept), so the secret it stands on may walk away.
    static func pairTag(_ conv: String) -> Data? { MTPipeBook.kept(for: conv)?.pair }
    private static func le(_ v: UInt64) -> Data { withUnsafeBytes(of: v.littleEndian) { p in Data(p) } }
    private static func u64(_ b: [UInt8], _ at: Int) -> UInt64 {
        (0..<8).reduce(UInt64(0)) { v, i in v | (UInt64(b[at + i]) << (8 * UInt64(i))) }
    }
    /// The record of version 2, signed by the core on top of the key's head (nil: no words, no pipe, or the core refused).
    static func build(_ coins: Int, conv: String, prev: String) -> Data? {
        guard 0 < coins, let k = keys(), let pair = pairTag(conv), let p = unhex(prev), p.count == 32 else { return nil }
        var nonce = [UInt8](repeating: 0, count: 16)
        guard SecRandomCopyBytes(kSecRandomDefault, nonce.count, &nonce) == errSecSuccess else { return nil }
        var body = magic
        body.append(2)
        body.append(le(UInt64(coins)))
        body.append(le(UInt64(max(0, Date().timeIntervalSince1970 * 1000))))
        body.append(contentsOf: nonce)
        body.append(pair)
        body.append(p)
        body.append(k.pk)
        guard body.count == 2053, let sig = MontanaPQ.sign(seckey: k.sk, message: signed2 + body), sig.count == 3309 else { return nil }
        return body + sig
    }
    static func name(_ rec: Data) -> String { hex(Data(SHA256.hash(data: rec))) }
    /// A record read back -- version 1 or 2 -- believed only when its shape holds and the core verifies its signature. known: the
    /// caller already saw a record of this very name verify, and the name is the hash of every byte, the signature's among them --
    /// the same bytes, the same answer; the caller still holds the read record's name to the one it knew.
    static func read(_ rec: Data, known: Bool = false) -> Record? {
        let b = [UInt8](rec)
        guard 5 <= b.count, Data(b[0..<4]) == magic else { return nil }
        let v = b[4]
        if v == 3 { return read3(rec, known: known) }
        let end: Int, keyAt: Int, total: Int, prefix: Data
        switch v {
        case 1: end = 2021; keyAt = 69; total = size; prefix = signed1
        case 2: end = 2053; keyAt = 101; total = size2; prefix = signed2
        default: return nil
        }
        guard b.count == total else { return nil }
        let coins = u64(b, 5)
        guard 0 < coins, coins <= UInt64(Int.max) else { return nil }
        let body = Data(b[0..<end]), pk = Data(b[keyAt..<end]), sig = Data(b[end..<total])
        guard known || MontanaPQ.verify(pubkey: pk, message: prefix + body, signature: sig) else { return nil }
        return Record(id: name(rec), version: v, coins: Int(coins), birthMs: u64(b, 13), pair: Data(b[37..<69]),
                      prev: v == 2 ? hex(Data(b[69..<101])) : "", from: keyTag(pk), bytes: rec)
    }
    private static func doors() -> [String] { MontanaWakePush.oneDoorPerNode(MontanaWakePush.orderedBases(for: "vault")) }
    /// A door's chain node: the node whose door it is, nil for any other door.
    private static func chainNode(ofDoor door: String) -> String? {
        guard let host = URL(string: door)?.host else { return nil }
        return chainNodes.first { n in n.host == host }?.name
    }
    /// A key's chain node: the one at the index of the key tag's first byte.
    static func chainNode(of from: String) -> String? {
        guard let first = UInt8(from.prefix(2), radix: 16) else { return nil }
        return chainNodes[Int(first) % chainNodes.count].name
    }
    /// THE DOOR OF A KEY'S CHAIN: its node through the api door when the phone knows it, else through any door of that node the
    /// phone holds, else through the node's own api name.
    static func chainDoor(_ from: String) -> String? {
        guard let node = chainNode(of: from) else { return nil }
        return door(ofNode: node)
    }
    private static func door(ofNode node: String) -> String? {
        chainNodes.first { n in n.name == node }.map { n in "https://" + n.host + "/pushwake" }
    }
    /// A node's answer, and whether the request never reached it (no network, no name, no connection): only such a silence
    /// proves nothing was laid there.
    private static func ask(_ url: String, _ body: [String: Any]) async -> (code: Int, obj: [String: Any]?, unreached: Bool) {
        guard let u = URL(string: url), let d = try? JSONSerialization.data(withJSONObject: body) else { return (-1, nil, true) }   // SERVER-DEBT-ACK: the accelerator node (rung 4), the transfers' log
        var req = URLRequest(url: u); req.httpMethod = "POST"; req.timeoutInterval = 15   // SERVER-DEBT-ACK: the accelerator node (rung 4)
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.httpBody = d
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)   // SERVER-DEBT-ACK: the accelerator node (rung 4)
            return ((resp as? HTTPURLResponse)?.statusCode ?? -1, try? JSONSerialization.jsonObject(with: data) as? [String: Any], false)
        } catch let e as URLError {
            let never: Set<URLError.Code> = [.notConnectedToInternet, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed, .dataNotAllowed, .internationalRoamingOff]
            return (-1, nil, never.contains(e.code))
        } catch {
            return (-1, nil, false)
        }
    }
    /// THE NODE'S WORD DECIDES (the keeper's state is said by the keeper): a version 2 record goes to its key's chain node alone --
    /// taken there, left; standing on a head that moved, behind; refused, or the request never reached it, not left; anything else
    /// waits for that node's word. A version 1 record (an older build's, settled here) keeps its own rule: any door that takes it.
    static func lay(_ rec: Data) async -> Word {
        let id = name(rec)
        let b = [UInt8](rec)
        guard 5 <= b.count else { return .notLeft }
        if b[4] == 2 && b.count == size2 || b[4] == 3 && b.count == size3 {
            guard let door = chainDoor(keyTag(b[4] == 2 ? Data(b[101..<2053]) : Data(b[182..<2134]))) else { return .notLeft }
            let a = await ask(door + "/tx-put", ["rec": rec.base64EncodedString()])
            if a.code == 200, (a.obj?["id"] as? String) == id { tookOne(); return .left }
            // THE NODE'S CODE AND WORD GO TO THE DIARY (T1 02.11.2026 11:15:12 UTC: «coin_v3 send word=notLeft» and nothing of why;
            // the node had said 429 «key pace»): a refusal is read by its code and its word, never guessed.
            MontanaTrace.mark("coin_lay", "code=\(a.code) error=\(a.obj?["error"] as? String ?? "-") unreached=\(a.unreached ? 1 : 0) id=\(id.prefix(12))")
            if a.code == 409 { return .behind }
            if a.code == 429 { return .paced }
            if a.code == 400 || a.code == 507 || a.unreached { return .notLeft }
            let g = await ask(door + "/tx-get", ["id": id])
            return g.code == 200 ? .left : .unknown
        }
        var refused = 0, unreached = 0, all = 0
        for door in doors() {
            all += 1
            let a = await ask(door + "/tx-put", ["rec": rec.base64EncodedString()])
            if a.code == 200, (a.obj?["id"] as? String) == id { return .left }
            if a.code == 400 || a.code == 507 { refused += 1 } else if a.unreached { unreached += 1 }
        }
        if 0 < all, refused + unreached == all { return .notLeft }
        for door in doors() {
            let a = await ask(door + "/tx-get", ["id": id])
            if a.code == 200 { return .left }
        }
        return .unknown
    }
    /// THE HEAD IS BELIEVED ONLY AS MY OWN SIGNED RECORD (the chairman's finding 11.10.2026 20:2x UTC: a node that took a record of my
    /// key signed by no one handed it out as my head, and the next honest record stood on it for ever): the head's record is read
    /// from the same chain node, its bytes must be its name, the core must verify it, and it must be of my own key. Anything else --
    /// no record, another key, a forgery -- and nothing is built on it: the coins stay.
    private static func headIsMine(_ head: String, me: String, door: String) async -> Bool {
        if head == zero { return true }
        let g = await ask(door + "/tx-get", ["id": head])
        guard g.code == 200, let b = (g.obj?["rec"] as? String).flatMap({ s in Data(base64Encoded: s) }) else { return false }
        guard let r = await Task.detached(priority: .userInitiated, operation: { read(b) }).value else { return false }
        return r.id == head && r.from == me && (r.version == 2 || r.version == 3)
    }
    private static func pendingURL(_ id: String) -> URL? { MTTimeChainPlace.dir()?.appendingPathComponent("tx-pending-" + id + ".rec") }
    /// SENDS (version 2): the key's head from its chain node, the record on top of it, the debit held under the record's name, the
    /// record laid there. Taken -- the coins left. A head that moved (another device of the words sent meanwhile) -- the coins come
    /// back under the same number, the seed's own records join the book, the balance is asked again and one more record goes on the
    /// new head. Refused, or never reached -- the coins come back. No answer -- the record waits on disk for the node's word (settle).
    enum SendResult { case sent(String), pending, refused, noKey, paced }
    @MainActor static func send(_ coins: Int, conv: String) async -> String? {
        if case let .sent(id) = await sendResult(coins, conv: conv) { return id }
        return nil
    }
    @MainActor static func sendResult(_ coins: Int, conv: String) async -> SendResult {
        // VERSION 3 FIRST (COIN-TX-V3): the chain proves the balance; version 2 only for a correspondent who cannot take v3, until the cut
        switch await send3(coins, conv: conv) {
        case .sent(let id): return .sent(id)
        case .pending: return .pending
        case .failed: return .refused
        case .paced: return .paced
        case .notApplicable(let why):
            // the reason a version 3 SEND could not go, said: 08:59:58 UTC of 12.10 laid a v2 record and nothing told why
            MontanaTrace.mark("coin_v3", "v2 road why=\(why) coins=\(coins)")
            if v2Cut <= Int64(Date().timeIntervalSince1970) { return why == noReceiverKey ? .noKey : .refused }
        }
        let seat = MTCoinSeat()
        guard let me = myKeyTag, let door = chainDoor(me) else { return .refused }
        // A SEND THAT NAMES NO RECEIVER SPENDS THE CHAIN TOO (COIN-TX-V3 section 3, fold-2): the chain opened and holding the sum first,
        // else the node refuses it as an overspend -- the coins stay, said here before anything is signed
        if let st = await reconcile(force: true), st.v3, st.proven + st.declared < Int64(coins) {
            MontanaTrace.mark("coin_v3", "v2 road refused: chain short coins=\(coins) chain=\(st.proven + st.declared)")
            return .refused
        }
        for attempt in 1...2 {
            let h = await ask(door + "/tx-head", ["from": me])
            guard h.code == 200, let head = h.obj?["head"] as? String, head.count == 64 else {
                MontanaTrace.mark("coin_tx", "no head code=\(h.code) attempt=\(attempt)")
                return .refused
            }
            guard await headIsMine(head, me: me, door: door) else {
                MontanaTrace.mark("coin_tx", "head unverified attempt=\(attempt)")
                return .refused
            }
            guard let rec = await Task.detached(priority: .userInitiated, operation: { build(coins, conv: conv, prev: head) }).value else {
                MontanaTrace.mark("coin_tx", "refused build coins=\(coins)")
                return .refused
            }
            let id = name(rec)
            guard let book = seat.book, book.send(coins, to: conv, ref: refPrefix + id) else { return .refused }
            let pending = pendingURL(id)
            if let pending { MTDiskDoor.write(rec, to: pending, "coin-pending", options: .atomic) }
            let word = await lay(rec)
            MontanaTrace.mark("coin_tx", "word=\(word) coins=\(coins) id=\(id.prefix(12)) attempt=\(attempt)")
            guard seat.stands else { return .pending }   // the record waits in its person's folder (settle)
            switch word {
            case .left:
                if let pending { try? FileManager.default.removeItem(at: pending) }
                return .sent(id)
            case .notLeft, .behind, .paced:
                book.receive(coins, from: conv, ref: backPrefix + id, on: nil)
                if let pending { try? FileManager.default.removeItem(at: pending) }
                if word == .notLeft { return .refused }
                if word == .paced { return .paced }
                await scanFresh(why: "behind")   // the other device's record joins the book before the balance is asked again
            case .unknown:
                return .pending
            }
        }
        return .refused
    }
    /// The records an ended process left waiting, each decided by a node's word; then the pipes are asked.
    @MainActor static func settle() async {
        let seat = MTCoinSeat()
        let fm = FileManager.default
        if let dir = MTTimeChainPlace.dir() {
            for n in (try? fm.contentsOfDirectory(atPath: dir.path)) ?? [] where n.hasPrefix("tx-pending-") && n.hasSuffix(".rec") {
                let u = dir.appendingPathComponent(n)
                guard let rec = try? Data(contentsOf: u), let r = read(rec) else { try? fm.removeItem(at: u); continue }
                let conv = MTPipeBook.all().first { c in pairTag(c) == r.pair }
                let word = await lay(rec)
                guard let book = seat.book else { return }   // the records wait in their person's folder
                switch word {
                case .left: try? fm.removeItem(at: u)
                case .notLeft, .behind:
                    if let conv { book.receive(r.coins, from: conv, ref: backPrefix + r.id, on: book.entry(.send, refPrefix + r.id)?.on) }
                    try? fm.removeItem(at: u)
                case .unknown, .paced: continue   // paced: the record stays in its folder, the next settle lays it again
                }
            }
        }
        await scan(why: "launch")
    }
    @MainActor private static var scanning = false
    @MainActor private static var again = false
    /// A scan that starts after the one in flight ends: what the node holds now is in the book when it returns.
    @MainActor private static func scanFresh(why: String) async {
        for _ in 0..<150 where scanning { try? await Task.sleep(nanoseconds: 100_000_000) }
        await scan(why: why)
    }
    /// The doors asked for records: each chain node's door, then the phone's other doors (version 1 records of older builds).
    private static func scanDoors() -> [String] {
        var out = chainNodes.compactMap { n in door(ofNode: n.name) }
        for d in doors() where chainNode(ofDoor: d) == nil { out.append(d) }
        return out
    }
    /// RECEIVES: every pipe's tag asked on every node; a verified record from another key is a credit, a record from my own key my
    /// own send from another device of the words -- each once, by its name; a version 2 record is believed only from its key's
    /// chain node, so a record laid on another node (a fork a dishonest client tried) moves nothing.
    @MainActor static func scan(why: String) async {
        if scanning { again = true; return }
        let seat = MTCoinSeat()
        guard let me = myKeyTag else { return }
        var conv: [String: String] = [:]
        for c in MTPipeBook.all() { if let t = pairTag(c) { conv[hex(t)] = c } }
        guard !conv.isEmpty else { return }
        scanning = true
        defer {
            scanning = false
            if again { again = false; Task { @MainActor in await scan(why: "again") } }
        }
        let tags = Array(conv.keys)
        var got = 0, credited = 0, own = 0, bad = 0, foreign = 0
        var seen = Set<String>()
        for door in scanDoors() {
            let node = chainNode(ofDoor: door)
            for start in stride(from: 0, to: tags.count, by: 256) {
                let part = Array(tags[start..<min(start + 256, tags.count)])
                var since = 0
                while true {
                    let a = await ask(door + "/tx-pair", ["tags": part, "since": since])
                    guard a.code == 200, let txs = a.obj?["txs"] as? [[String: Any]] else { break }
                    for x in txs {
                        guard let id = x["id"] as? String, !seen.contains(id),
                              let b = (x["rec"] as? String).flatMap({ s in Data(base64Encoded: s) }) else { continue }
                        got += 1
                        guard let r = await Task.detached(priority: .utility, operation: { read(b) }).value, r.id == id,
                              let c = conv[hex(r.pair)] else { bad += 1; continue }
                        if r.version != 1, chainNode(of: r.from) != node { foreign += 1; continue }
                        seen.insert(id)
                        guard let book = seat.book else { return }   // the pipes and the key were the person's who left
                        if r.from == me {
                            if !book.holds(.send, refPrefix + r.id), book.retake(r.coins, to: c, ref: refPrefix + r.id) { own += 1 }
                        } else if r.version == 3 {
                            if await receive3(r, conv: c) { credited += 1 }
                        } else {
                            if book.receive(r.coins, from: c, ref: refPrefix + r.id, on: nil) { credited += 1 }
                            if r.version == 2, book.holds(.receive, refPrefix + r.id) { noteCredit2(r.id, from: r.from, coins: r.coins, conv: c) }
                        }
                    }
                    let last = a.obj?["last"] as? Int ?? since
                    guard txs.count == 512, since < last else { break }
                    since = last
                }
            }
        }
        MontanaTrace.mark("coin_tx_scan", "why=\(why) pipes=\(conv.count) got=\(got) credited=\(credited) own=\(own) bad=\(bad) foreign=\(foreign)")
        guard seat.stands else { return }
        await reconcile()       // the chain announced and the book's mints laid (COIN-TX-V3 sections 3-4)
        await refundDue()       // a SEND no one took in a day comes back (section 5)
        await creditsGone()     // a v2 record its sender took back leaves this book too (fold-4)
        await MTCoinReplica.run(why: why)   // this phone's copy of the network's chains and its signed root (section 6)
    }
}

// MARK: - version 3 (Audit/COIN-TX-V3.md): every move of a key's balance is a signed record of its chain
/// THE BALANCE IS THE FOLD OF THE KEY'S CHAIN (the author's words 11.10.2026 19:5x UTC: "balances must be proven ... the Explorer
/// shows the proof of it locally and globally"; 20:5x: "take the proven balance yourself, check it as the critic and do it
/// yourself"). The book stays the phone's ledger; the chain is what anyone can fold: the key's first v3 record announces the book
/// (GENESIS, declared, never called proven), what the book holds above the chain is laid as a MINT within the time of its interval,
/// a SEND names the receiver's key under a blind only the pair opens, the receiver's RECV takes it, and an untaken SEND comes back
/// by a REFUND after a day. The node of the key's chain folds every record and refuses an overspend; so do the replicas, the phones
/// that keep a copy and the Explorer.
extension MTCoinTx {
    static let size3 = 5443
    typealias Kind3 = MTCoinChainRules.Kind
    private static let signed3 = Data("mt-coin-tx-v3".utf8)
    static var v2Cut: Int64 { MTCoinChainRules.v2Cut }
    static func fresh() -> Data {
        var n = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, n.count, &n)
        return Data(n)
    }
    /// The record of version 3, signed by the core (nil: no words, a field of the wrong size, or the core refused).
    static func build3(_ kind: Kind3, amount: UInt64, prev: String, nonce: Data, pair: Data = Data(count: 32), to: Data = Data(count: 32),
                       ref: String = zero, a: UInt64 = 0, b: UInt64 = 0, hands: Hands? = nil) -> Data? {
        guard let k = hands.map({ h in (pk: h.pk, sk: h.sk) }) ?? keys(), let p = unhex(prev), p.count == 32, let r = unhex(ref), r.count == 32, nonce.count == 16,
              pair.count == 32, to.count == 32 else { return nil }
        var body = magic
        body.append(3); body.append(kind.rawValue)
        body.append(le(amount)); body.append(le(UInt64(max(0, Date().timeIntervalSince1970 * 1000))))
        body.append(nonce); body.append(p); body.append(pair); body.append(to); body.append(r)
        body.append(le(a)); body.append(le(b)); body.append(k.pk)
        guard body.count == 2134, let sig = MontanaPQ.sign(seckey: k.sk, message: signed3 + body), sig.count == 3309 else { return nil }
        return body + sig
    }
    /// A record of version 3 read back -- believed only when its shape holds and the core verifies its signature.
    static func read3(_ rec: Data, known: Bool = false) -> Record? {
        let b = [UInt8](rec)
        guard b.count == size3, Data(b[0..<4]) == magic, b[4] == 3, let kind = Kind3(rawValue: b[5]) else { return nil }
        let amount = u64(b, 6)
        guard amount <= UInt64(Int.max), 0 < amount || kind == .genesis else { return nil }
        guard MTCoinChainRules.fieldsHold(kind: kind.rawValue, amount: amount, pair: Data(b[70..<102]), to: Data(b[102..<134]), ref: Data(b[134..<166]),
                                     a: u64(b, 166), b: u64(b, 174)) else { return nil }
        let body = Data(b[0..<2134]), pk = Data(b[182..<2134]), sig = Data(b[2134..<size3])
        guard known || MontanaPQ.verify(pubkey: pk, message: signed3 + body, signature: sig) else { return nil }
        var r = Record(id: name(rec), version: 3, coins: Int(amount), birthMs: u64(b, 14), pair: Data(b[70..<102]),
                       prev: hex(Data(b[38..<70])), from: keyTag(pk), bytes: rec)
        r.kind = kind.rawValue; r.to = Data(b[102..<134]); r.ref = hex(Data(b[134..<166])); r.a = u64(b, 166); r.b = u64(b, 174)
        r.nonce = Data(b[22..<38])
        return r
    }
    /// The state of a key's chain as its node folds it (POST /tx-head), and the node's own second.
    struct Chain3 { let head: String; let height: Int; let birth: Int64; let mintEnd: Int64; let proven: Int64; let declared: Int64; let v3: Bool; let now: Int64; let minted: Int64? }
    static func chain3(_ me: String, door: String) async -> Chain3? {
        let h = await ask(door + "/tx-head", ["from": me])
        guard h.code == 200, let o = h.obj, let head = o["head"] as? String, head.count == 64 else {
            // THE ROAD THAT FAILED IS SAID (link 11336, 29.10.2026): a silent nil left the diary of 13498CA8 with no word of why the
            // chain never answered; the node and the code are told, folded over ten minutes, never the key.
            MontanaTrace.markFolded("coin_chain3", "code=\(h.code) unreached=\(h.unreached ? 1 : 0) node=\(chainNode(ofDoor: door) ?? "?")", window: 600)
            return nil
        }
        func n(_ k: String) -> Int64 {
            if let s = o[k] as? String { return Int64(s) ?? 0 }
            return (o[k] as? NSNumber)?.int64Value ?? 0
        }
        let now = n("now")
        return Chain3(head: head, height: Int(n("height")), birth: n("birth"), mintEnd: n("mint_end"), proven: n("proven"),
                      declared: n("declared"), v3: n("v3") == 1, now: now == 0 ? Int64(Date().timeIntervalSince1970) : now,
                      minted: o["minted"] == nil ? nil : n("minted"))
    }
    /// One record of my key laid on my chain's head, the head read back and verified as mine first; a head that moved is asked
    /// again once. (the node's code, its word, the record laid).
    @MainActor static func layOnHead(hands: Hands? = nil, _ make: (Chain3) -> Data?) async -> (code: Int, word: String, rec: Data?) {
        guard let me = hands?.from ?? myKeyTag, let door = chainDoor(me) else { return (-1, "no key", nil) }
        for _ in 0..<2 {
            guard let st = await chain3(me, door: door) else { return (-1, "no head", nil) }
            guard await headIsMine(st.head, me: me, door: door) else { return (-1, "head unverified", nil) }
            guard let rec = make(st) else { return (-1, "no record", nil) }
            let a = await ask(door + "/tx-put", ["rec": rec.base64EncodedString()])
            let word = (a.obj?["error"] as? String) ?? ""
            if a.code == 200 { return (200, "", rec) }
            if a.code == 409, word == "not on the head" { continue }
            if a.code == -1, !a.unreached, (await ask(door + "/tx-get", ["id": name(rec)])).code == 200 { return (200, "", rec) }
            return (a.code, word, rec)
        }
        return (409, "not on the head", nil)
    }
    @MainActor private static var mintedAt: TimeInterval = 0
    @MainActor private static var mintDue = false
    /// THE BOOK'S MOVE ASKS ITS CHAIN WITHIN ONE WINDOW (the author's words 12.10.2026 12:5x UTC: «the minting has its own chain of time
    /// and as it is confirmed it releases the available»; «once in τ1»): one ask a window, however many coins the window holds.
    @MainActor static func mintSoon() {
        guard !mintDue else { return }
        mintDue = true
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(MTCoinChainRules.window)) {
            MainActor.assumeIsolated {
                mintDue = false
                Task { @MainActor in await reconcile() }
            }
        }
    }
    /// THE PERSON HERE MINTS (fold-7): online -- the app in front of the person -- or behind the living tunnel of the VPN.
    @MainActor static var here: Bool {
        UIApplication.shared.applicationState != .background || MTApps.vpn?.connected == true
    }
    /// The seconds the road to the node may take: a MINT reaching it later than this counts less than it names.
    nonisolated static let presentMargin: Int64 = 20
    /// Under the node's minute plus one beat, a MINT's interval never passes the freshness less the margin: no second here is lost.
    nonisolated static let presentBeat: UInt64 = 40
    @MainActor private static var presence: Task<Void, Never>?
    /// THE NODE SECOND THE PERSON CAME (the author's words 26.10.2026 09:2x UTC, links 8615 and 8617: «show how the coins are minted
    /// every second ... so that it works right over the network too»; «let it count so, then show visually what happens before the
    /// window is finalized»): the first second of this stay the chain's node told, nil while the person is away. A MINT counts from
    /// it and never from before it -- minting happens while the person is here (fold-7) -- and the wallet shows the same seconds
    /// rising while they are on their way (MTCoinSplit.minting).
    @MainActor private(set) static var hereFrom: Int64?
    /// The app came to the screen, the wallet opened or the tunnel rose: while the person stays here every beat asks the chain --
    /// before the online cut only to read the key's life the chain mints itself (fold-6), so the person's number grows with the chain
    /// and never by the book, which mints nothing after the time cut (MTLocalCoinLedger.priced).
    @MainActor static func beHere() {
        // A stay the app's leaving closed reopens on its return at once, even inside a beat that still sleeps: the beat already
        // running would not open it again, and every second until that beat ended would rise nowhere (MTPresenceWait.watch).
        if here { MTPresenceWait.open() }
        guard presence == nil else { return }
        hereFrom = nil
        presence = Task { @MainActor in
            MTPresenceWait.open()   // the seconds in the network wait for the core from here (decision 443)
            while !Task.isCancelled, here {
                await reconcile()
                MTPresenceWait.fold()
                try? await Task.sleep(nanoseconds: presentBeat * 1_000_000_000)
            }
            MTPresenceWait.close()
            presence = nil
            hereFrom = nil
            MTCoinSplit.shared.beat()
        }
    }
    /// THE CHAIN HOLDS WHAT THE BOOK HOLDS (sections 3-4). A key's first v3 record is its GENESIS: the book as it stands, at most
    /// what time could have minted since the coins began, announced and never called proven (before the v2 cut; a GENESIS of 0
    /// after it). After it, what the book holds above the chain is laid as a MINT of the time since the last one, at most what the
    /// interval allows -- once a window of τ1 (MTCoinChainRules.window), or at once when a send needs it. The node's clock decides the
    /// interval, never the phone's.
    @MainActor @discardableResult static func reconcile(force: Bool = false) async -> Chain3? {
        guard let me = myKeyTag, let door = chainDoor(me) else { return nil }
        // ONE PERSON'S BOOK ON ONE PERSON'S CHAIN (the critic 19.10.2026, T2: the author's word 20:25 «a separate person, wholly
        // separate»): a seat that moves during a wait seats another key and another book -- the book read before it would be laid on
        // the next person's chain. Every record is built only while the seat that began this stands and its key is the one laying.
        let seat = MTCoinSeat()
        guard var st = await chain3(me, door: door) else { return nil }
        // what the chain's node folds is told to the wallet's split, after every word of it
        func told(_ s: Chain3?) -> Chain3? {
            if let s, seat.stands { MTCoinSplit.shared.heard(proven: s.proven, declared: s.declared, opened: s.v3, fromCopy: false, height: s.height, second: s.now, mintEnd: s.mintEnd) }
            return s
        }
        guard seat.stands else { MontanaTrace.mark("coin_v3", "the seat moved -- nothing laid"); return nil }
        let book = Int64(MTLocalCoinLedger.shared.whole.balance)
        if !st.v3 {
            let amount = min(max(0, book), MTCoinChainRules.genesisRoom(height: st.height, birth: st.birth, at: st.now))
            let r = await layOnHead { s in seat.stands ? build3(.genesis, amount: UInt64(amount), prev: s.head, nonce: fresh()) : nil }
            MontanaTrace.mark("coin_v3", "genesis code=\(r.code) word=\(r.word) amount=\(amount)")
            guard r.code == 200, let again = await chain3(me, door: door) else { return nil }
            st = again
        }
        // ONLY THE CHAIN MINTS (section 4, fold-6): from the node's TX_TIME_CUT the chain credits the key's seconds itself, so the phone
        // lays no MINT and shows the fold /tx-head answers -- until the node's TX_ONLINE_CUT, past which a key's life mints nothing by itself
        guard st.now < MTCoinChainRules.timeCut else {
            // MINTING IS ITS OWN ROAD (fold-7; the author's words 23.10.2026 00:27 and 00:37 UTC: «minting is a separate entity, and it
            // happens if the person is online or behind the VPN»): the node counts of a MINT only what its interval holds of the last
            // mintFresh seconds before it takes it, so while the person is here the phone lays the seconds since the last MINT, never
            // older than the freshness less the road's margin; the node's minute between two MINTs is the pace
            if here, presence != nil, hereFrom == nil, MTCoinChainRules.onlineCut <= st.now { hereFrom = st.now }
            guard MTCoinChainRules.onlineCut <= st.now, st.now < MTCoinChainRules.mintStop, here, st.mintEnd + 60 <= st.now else { return told(st) }
            let from = hereFrom ?? st.now
            let r = await layOnHead { s in
                guard seat.stands, 0 < s.height, MTCoinChainRules.onlineCut <= s.now, s.now < MTCoinChainRules.mintStop else { return nil }
                let t1 = s.now, t0 = max(s.mintEnd, t1 - MTCoinChainRules.mintFresh + presentMargin, from)
                // the present seconds alone weigh it (fold-8): the life the node credited up to the online cut is not asked again
                let amount = MTCoinChainRules.present(t0: t0, t1: t1, at: t1 + presentMargin)
                guard 0 < amount, t0 + 60 <= t1 else { return nil }
                return build3(.mint, amount: UInt64(amount), prev: s.head, nonce: fresh(), a: UInt64(t0), b: UInt64(t1))
            }
            MontanaTrace.mark("coin_v3", "present mint code=\(r.code) word=\(r.word)")
            return told(r.code == 200 ? await chain3(me, door: door) : st)
        }
        let wall = Date().timeIntervalSince1970
        guard force || Double(MTCoinChainRules.window) <= wall - mintedAt else { return told(st) }
        mintedAt = wall
        let gap = book - st.proven - st.declared
        guard 0 < gap, st.mintEnd + 60 <= st.now - 120 else { return told(st) }
        let r = await layOnHead { s in
            guard seat.stands else { return nil }
            let t0 = s.mintEnd, t1 = s.now - 120
            // the key's time less what it minted (section 4, fold-3; from the second's cut 1 coin a second, weighed at the node's now,
            // the at it gives the record); a node that names no minted still folds by the interval
            let room = MTCoinChainRules.allowTime(t1 - s.birth, at: s.now) - (s.minted ?? MTCoinChainRules.allowTime(t0 - s.birth, at: s.now))
            let amount = min(book - s.proven - s.declared, room)
            guard 0 < amount, t0 + 60 <= t1 else { return nil }
            return build3(.mint, amount: UInt64(amount), prev: s.head, nonce: fresh(), a: UInt64(t0), b: UInt64(t1))
        }
        MontanaTrace.mark("coin_v3", "mint code=\(r.code) word=\(r.word) gap=\(gap)")
        return told(r.code == 200 ? await chain3(me, door: door) : st)
    }
    // -- the correspondents' coin keys, my open sends: files of the TimeChain's own folder (staying on the device). No lock over the
    // files (the layout law: a lock holds a word in memory, never a disk): the open sends are touched only on the main actor, and a
    // correspondent's key lost to a race comes again with their next about word. --
    private static func load(_ name: String) -> [String: Any] {
        guard let u = MTTimeChainPlace.dir()?.appendingPathComponent(name), let d = try? Data(contentsOf: u),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return [:] }
        return o
    }
    private static func save(_ name: String, _ o: [String: Any]) {
        guard let u = MTTimeChainPlace.dir()?.appendingPathComponent(name), let d = try? JSONSerialization.data(withJSONObject: o) else { return }
        MTDiskDoor.write(d, to: u, "coin-tx-state", options: .atomic)
    }
    /// A correspondent's coin key, told in their about word (k): the key a SEND of version 3 commits to.
    static func peerFrom(_ conv: String) -> String? { (load("coin3-peers.json")["k"] as? [String: String])?[conv] }
    static func notePeerFrom(_ conv: String, _ from: String) {
        guard from.count == 64, from.allSatisfy({ ch in ch.isHexDigit }) else { return }
        var o = load("coin3-peers.json")
        var m = (o["k"] as? [String: String]) ?? [:]
        guard m[conv] != from else { return }
        m[conv] = from; o["k"] = m
        save("coin3-peers.json", o)
    }
    /// Whether this correspondent was already told my coin key (the about word carries it until then).
    static func toldKey(_ conv: String, _ k: String) -> Bool { (load("coin3-peers.json")["told"] as? [String: String])?[conv] == k }
    static func noteToldKey(_ conv: String, _ k: String) {
        var o = load("coin3-peers.json")
        var m = (o["told"] as? [String: String]) ?? [:]
        m[conv] = k; o["told"] = m
        save("coin3-peers.json", o)
    }
    static func forgetToldKey(_ conv: String) {
        var o = load("coin3-peers.json")
        var m = (o["told"] as? [String: String]) ?? [:]
        guard m.removeValue(forKey: conv) != nil else { return }
        o["told"] = m
        save("coin3-peers.json", o)
    }
    /// THE KEY DERIVED FOR THE WORD ABOUT ONESELF (the author's word 21.10.2026 09:41 UTC, E2E.sendAboutIfNeeded): once at a time,
    /// off the main thread; when it stands, every correspondent not yet told hears it.
    private static var deriving = false
    static func deriveForTheWord() {
        keyLock.lock(); let busy = deriving; deriving = true; keyLock.unlock()   // LOCK-OK: one flag
        guard !busy else { return }
        DispatchQueue.global(qos: .utility).async {
            let k = keys()
            keyLock.lock(); deriving = false; keyLock.unlock()   // LOCK-OK: one flag
            guard k != nil else { return }
            DispatchQueue.main.async { E2E.shared.broadcastAbout() }
        }
    }
    /// The coin key already derived in this process, never derived here (a main-thread caller must not pay the seed's derivation).
    static var cachedKeyTag: String? {
        keyLock.lock(); let c = keyCache; keyLock.unlock()   // LOCK-OK: one read of the cached key
        return c.map { k in keyTag(k.pk) }
    }
    private static func openSends() -> [[String: Any]] { (load("coin3-open.json")["open"] as? [[String: Any]]) ?? [] }
    private static func keepOpen(_ rows: [[String: Any]]) { save("coin3-open.json", ["open": rows]) }
    /// THE LETTER A PAID REACTION'S SEND STANDS UNDER, AS ITS WORD NAMED IT (MTCoinSend.give): the word moves no coins; it names
    /// the SEND, and the scan asked at once credits that SEND under the letter. A word later than the scan leaves the coins right
    /// and under no letter. The newest 256 names are kept.
    @MainActor static func heard(_ tx: String, on sid: String) {
        guard tx.count == 64, tx.allSatisfy({ ch in ch.isHexDigit }), !sid.isEmpty else { return }
        var rows = ((load(heardFile)["on"] as? [[String]]) ?? []).filter { r in r.first != tx }
        rows.append([tx, sid])
        save(heardFile, ["on": Array(rows.suffix(256))])
        guard !MTLocalCoinLedger.shared.whole.holds(.receive, refPrefix + tx) else { return }
        Task { @MainActor in await scanFresh(why: "reaction") }
    }
    private static let heardFile = "coin3-heard.json"
    private static func heardOn(_ tx: String) -> String? {
        ((load(heardFile)["on"] as? [[String]]) ?? []).last { r in r.first == tx }.flatMap { r in r.count == 2 ? r[1] : nil }
    }
    /// A name taken once (an auto-reaction's «auto:» and its letter): false if it stands. Two days are kept -- an auto-reaction pays
    /// only a letter born within a day (MTCoinSend.fresh).
    @MainActor static func once(_ name: String) -> Bool {
        let now = Date().timeIntervalSince1970
        var o = ((load(onceFile)["n"] as? [String: Double]) ?? [:]).filter { _, at in now - at < 2 * MTCoinSend.fresh }
        guard o[name] == nil else { return false }
        o[name] = now
        save(onceFile, ["n": o])
        return true
    }
    @MainActor static func release(_ name: String) {
        var o = (load(onceFile)["n"] as? [String: Double]) ?? [:]
        o[name] = nil
        save(onceFile, ["n": o])
    }
    private static let onceFile = "coin3-once.json"
    enum Send3 { case sent(String), pending, notApplicable(String), failed, paced }   // paced: the key's node took its thirty records this minute and the next, nothing left
    private static let noReceiverKey = "no receiver key"   // NOT-UI: the trace's reason, and the one the send page names
    /// SENDS (version 3): the receiver's key known (their about word), my chain announced and holding the sum, the record names
    /// the declared part of it (proven is spent first), commits to the receiver's key under the pair's blind, and is laid on my
    /// chain's head. Anything that makes v3 impossible (an older correspondent, the chain not holding the sum yet) is said as
    /// notApplicable -- the version 2 road takes it until the cut.
    @MainActor static func send3(_ coins: Int, conv: String, on target: String? = nil) async -> Send3 {
        let seat = MTCoinSeat()
        guard let me = myKeyTag, let door = chainDoor(me), let pipe = MTPipeBook.key(for: conv), pipe.isWhole,
              let pair = pairTag(conv) else { return .notApplicable("no pipe") }
        guard let peer = peerFrom(conv), let peerBytes = unhex(peer), peerBytes.count == 32 else { return .notApplicable(noReceiverKey) }
        guard let first = await reconcile(force: true), first.v3, Int64(coins) <= first.proven + first.declared else { return .notApplicable("chain short") }
        let nonce = fresh()
        let blind = pipe.blind(nonce: nonce, by: MTCoinChainRules.blind(secret:nonce:))   // the item key's blind, made by the pipe's owner
        let commit = MTCoinChainRules.commitment(from: peerBytes, blind: blind)
        for attempt in 1...2 {
            guard let st = await chain3(me, door: door), st.v3, Int64(coins) <= st.proven + st.declared else { return .notApplicable("chain short") }
            guard await headIsMine(st.head, me: me, door: door) else { return .failed }
            guard let book = seat.book else { return .failed }
            let dec = max(0, Int64(coins) - st.proven)
            guard let rec = build3(.send, amount: UInt64(coins), prev: st.head, nonce: nonce, pair: pair, to: commit, a: UInt64(dec)) else { return .failed }
            let id = name(rec)
            guard book.sendHeld(coins, to: conv, ref: refPrefix + id, on: target) else { return .failed }
            let pending = pendingURL(id)
            if let pending { MTDiskDoor.write(rec, to: pending, "coin-pending", options: .atomic) }
            var word = await lay(rec)
            // THE KEY'S PACE IS WAITED, NOT REFUSED (the author's word 14463, 02.11.2026: 500 coins from T1 to the iPhone 11 at
            // 11:15:12 UTC «did not leave»). The node takes thirty records a minute from one key (V3 section 7, TX_KEY_PM); T1 had
            // laid thirty reactions of one coin in that minute, the node said 429 «key pace», and the phone said notLeft at once and
            // gave the coins back. The record stands as it is -- the head is mine and did not move -- and goes again every five
            // seconds till the minute frees, a minute at most; a head that moved meanwhile answers 409 and the next attempt builds on it.
            var paced = 0
            while word == .paced, paced < 12 {
                paced += 1
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                word = await lay(rec)
            }
            MontanaTrace.mark("coin_v3", "send word=\(word) coins=\(coins) dec=\(dec) id=\(id.prefix(12)) attempt=\(attempt) paced=\(paced)")
            guard seat.stands else { return .pending }   // the record waits in its person's folder (settle)
            switch word {
            case .left:
                if let pending { try? FileManager.default.removeItem(at: pending) }
                keepOpen(openSends() + [["id": id, "conv": conv, "coins": coins, "at": st.now]])
                MTCoinSplit.shared.laid(id, coins: coins, on: st.height)
                return .sent(id)
            case .notLeft, .behind, .paced:
                book.receive(coins, from: conv, ref: backPrefix + id, on: target)
                if let pending { try? FileManager.default.removeItem(at: pending) }
                if word == .notLeft { return .failed }
                if word == .paced { return .paced }   // a minute of waiting did not free the key: the coins are back, the person is told
            case .unknown:
                keepOpen(openSends() + [["id": id, "conv": conv, "coins": coins, "at": st.now]])
                MTCoinSplit.shared.laid(id, coins: coins, on: st.height)
                return .pending
            }
        }
        return .failed
    }
    /// RECEIVES (version 3): a SEND of my pair that commits to my key is taken by a RECV on my chain -- the book credits it only
    /// when my chain holds it (200, or another device of my words took it: the SEND's node names me).
    @MainActor static func receive3(_ s: Record, conv: String) async -> Bool {
        let seat = MTCoinSeat()
        guard s.kind == Kind3.send.rawValue, let me = myKeyTag, let mine = unhex(me),
              let pipe = MTPipeBook.key(for: conv), pipe.isWhole else { return false }
        guard let blind = pipe.blinds(nonce: s.nonce, by: MTCoinChainRules.blind(secret:nonce:))
                .first(where: { b in MTCoinChainRules.commitment(from: mine, blind: b) == s.to }) else { return false }
        let book = MTLocalCoinLedger.shared.whole
        if book.holds(.receive, refPrefix + s.id) { return false }
        guard let st = await reconcile(), st.v3 else { return false }
        let r = await layOnHead { c in seat.stands ? build3(.recv, amount: UInt64(s.coins), prev: c.head, nonce: fresh(), to: blind, ref: s.id, a: s.a) : nil }
        var taken = r.code == 200
        if !taken, r.word == "settled" || r.word == "not yours", let door = chainDoor(s.from) {
            let f = await ask(door + "/tx-settle", ["send": s.id])
            taken = (f.obj?["state"] as? String) == "recv" && (f.obj?["by"] as? String) == me
        }
        MontanaTrace.mark("coin_v3", "recv code=\(r.code) word=\(r.word) taken=\(taken ? 1 : 0) id=\(s.id.prefix(12))")
        return taken && seat.book?.receive(s.coins, from: conv, ref: refPrefix + s.id, on: heardOn(s.id)) == true
    }
    /// A TRANSFER TO ONE'S OWN OTHER ACCOUNT IS ONE PAIR, SENT AND RECEIVED IN THE SAME STEP (the author's words 12.10.2026 10:2x UTC:
    /// «either the coins left or not -- there is no third -- this is point 0»; 12:3x, No.66: «a transfer to oneself in Montana must
    /// become one pair of records, sent and received»). The phone holds both seeds -- the person seated and the person on its shelf --
    /// so the SEND names the other key (knowOwn), and the RECV is laid at once on the other key's own chain with that key, the chain
    /// opened first by its GENESIS of the book its shelf holds, as its own phone would open it. Only then do the coins stand in the
    /// other person's book on the nodes, under the name their own scan credits them by: a SEND whose RECV did not stand stays the
    /// receiver's to take when seated, or comes back to its sender by the REFUND after a day -- never both.
    @MainActor static func knowOwn(seat: String, conv: String) async -> Hands? {
        guard let shelf = await Task.detached(priority: .userInitiated, operation: { MTSeats.shelfCoins(seat) }).value,
              let hands = await Task.detached(priority: .userInitiated, operation: { derive(shelf.words) }).value else {
            MontanaTrace.mark("coin_own", "seat=\(seat) no hands")
            return nil
        }
        notePeerFrom(conv, hands.from)
        return hands
    }
    @MainActor static func landOwn(seat: String, send id: String, coins: Int, conv: String) async {
        guard let shelf = await Task.detached(priority: .userInitiated, operation: { MTSeats.shelfCoins(seat) }).value,
              let hands = await Task.detached(priority: .userInitiated, operation: { derive(shelf.words) }).value,
              let e = MontanaSeedKeys.entropyFrom(mnemonic: shelf.words), e.count == 32,
              let me = myKeyTag, let door = chainDoor(me) else {
            MontanaTrace.mark("coin_own", "seat=\(seat) no hands -- the receiver takes it when seated")
            return
        }
        var v3 = false, taken = false, said = "v2"
        let g = await ask(door + "/tx-get", ["id": id])
        if g.code == 200, let b = (g.obj?["rec"] as? String).flatMap({ s in Data(base64Encoded: s) }) {
            v3 = b.count == size3
            if v3, let s = await Task.detached(priority: .userInitiated, operation: { read3(b) }).value, s.id == id,
               let pipe = MTPipeBook.key(for: conv), pipe.isWhole, let theirs = unhex(hands.from), let tdoor = chainDoor(hands.from) {
                if let blind = pipe.blinds(nonce: s.nonce, by: MTCoinChainRules.blind(secret:nonce:))
                    .first(where: { b in MTCoinChainRules.commitment(from: theirs, blind: b) == s.to }) {
                    if let st = await chain3(hands.from, door: tdoor), !st.v3 {
                        let amount = min(max(0, Int64(shelf.book)), MTCoinChainRules.genesisRoom(height: st.height, birth: st.birth, at: st.now))
                        let r = await layOnHead(hands: hands) { c in build3(.genesis, amount: UInt64(amount), prev: c.head, nonce: fresh(), hands: hands) }
                        MontanaTrace.mark("coin_own", "seat=\(seat) genesis code=\(r.code) word=\(r.word) amount=\(amount)")
                    }
                    let r = await layOnHead(hands: hands) { c in
                        build3(.recv, amount: UInt64(s.coins), prev: c.head, nonce: fresh(), to: blind, ref: s.id, a: s.a, hands: hands)
                    }
                    taken = r.code == 200
                    said = "recv code=\(r.code) word=\(r.word)"
                } else { said = "not their key" }
            }
        } else { said = "no record code=\(g.code)" }
        guard taken || (g.code == 200 && !v3) else {
            MontanaTrace.mark("coin_own", "seat=\(seat) coins=\(coins) \(said) -- the receiver takes it when seated, or it comes back")
            return
        }
        let move = MTCoinEntry(k: .receive, c: coins, ref: refPrefix + id, peer: conv, on: nil, at: Date().timeIntervalSince1970)
        let laid = await MTCoinVault.lay([move], entropy: e)
        MontanaTrace.mark("coin_own", "seat=\(seat) coins=\(coins) \(said) book=\(laid) id=\(id.prefix(12))")
    }
    /// An untaken SEND comes back after a day by a REFUND on my chain (section 5): its node's clock decides, one fate a SEND.
    @MainActor static func refundDue() async {
        let seat = MTCoinSeat()
        guard let me = myKeyTag, let door = chainDoor(me) else { return }
        await refundSpent2(me: me, door: door, seat: seat)
        guard seat.stands else { return }
        let rows = openSends()
        guard !rows.isEmpty else { return }
        var left: [[String: Any]] = []
        for o in rows {
            guard let id = o["id"] as? String, let conv = o["conv"] as? String, let coins = o["coins"] as? Int else { continue }
            let at = (o["at"] as? NSNumber)?.int64Value ?? 0
            let f = await ask(door + "/tx-settle", ["send": id])
            guard let book = seat.book else { return }   // the open sends stay in their person's folder
            let state = (f.obj?["state"] as? String) ?? ""
            if state == "recv" { continue }
            if state == "refund" { book.receive(coins, from: conv, ref: backPrefix + id, on: book.entry(.send, refPrefix + id)?.on); continue }
            guard state == "open", let st = await chain3(me, door: door), at + 86_460 <= st.now else { left.append(o); continue }
            let r = await layOnHead { c in seat.stands ? build3(.refund, amount: UInt64(coins), prev: c.head, nonce: fresh(), ref: id) : nil }
            MontanaTrace.mark("coin_v3", "refund code=\(r.code) word=\(r.word) id=\(id.prefix(12))")
            guard let after = seat.book else { return }
            if r.code == 200 { after.receive(coins, from: conv, ref: backPrefix + id, on: after.entry(.send, refPrefix + id)?.on) } else { left.append(o) }
        }
        guard seat.stands else { return }
        keepOpen(left)
    }
}

extension MTCoinTx {
    /// A V2 RECORD THAT SPENT COMES BACK AFTER ITS DAY (fold-4, P-3 of Agent 95; the author's words 19.10.2026 09:2x UTC «put it in» and
    /// «at 16:23 I sent 1898535 from T1 to the Android»): a v2 record laid on my opened chain names no receiver, so no chain could ever take
    /// its coins -- 18.10 T1 sent 1 369 000 and 2 000 000 that way to an Android phone, which reads no chain, and they stood for no one.
    /// My chain's node names my unsettled sends (/tx-unsettled); a v2 one a day old is taken back by a REFUND, and the book receives it
    /// under the send's own name, from the pair the send left to. A v3 SEND keeps its own road (the open list in refundDue).
    @MainActor static func refundSpent2(me: String, door: String, seat: MTCoinSeat) async {
        let u = await ask(door + "/tx-unsettled", ["from": me])
        guard u.code == 200, let rows = u.obj?["sends"] as? [[String: Any]], !rows.isEmpty, let st = await chain3(me, door: door) else { return }
        for o in rows {
            guard (o["v"] as? NSNumber)?.intValue == 2, let id = o["id"] as? String, let coins = Int((o["amount"] as? String) ?? ""),
                  let at = (o["at"] as? NSNumber)?.int64Value, at + 86_460 <= st.now else { continue }
            let r = await layOnHead { c in seat.stands ? build3(.refund, amount: UInt64(coins), prev: c.head, nonce: fresh(), ref: id) : nil }
            MontanaTrace.mark("coin_v3", "refund v2 code=\(r.code) word=\(r.word) coins=\(coins) id=\(id.prefix(12))")
            guard let book = seat.book else { return }
            if r.code == 200 { book.receive(coins, from: book.entry(.send, refPrefix + id)?.peer ?? "", ref: backPrefix + id, on: nil) }
        }
    }
    /// The v2 records this book credited, each with its sender's key, its coins and its pair: a REFUND by the sender takes them back.
    private static let credits2File = "coin2-credits.json"
    private static let gonePrefix = "txgone:"   // NOT-UI: the book's name of a credit its sender took back
    static func noteCredit2(_ id: String, from: String, coins: Int, conv: String) {
        var o = load(credits2File)
        var m = (o["c"] as? [String: [String: Any]]) ?? [:]
        guard m[id] == nil else { return }
        m[id] = ["f": from, "n": coins, "p": conv]; o["c"] = m
        save(credits2File, o)
    }
    /// THE COINS ARE EITHER GONE OR NOT (constitution, article 8): a v2 record credited here whose sender's REFUND took it back at its
    /// chain node leaves this book by one move under its name, whatever the balance (retake: the truth of a debt). Asked once an hour.
    @MainActor static func creditsGone() async {
        let seat = MTCoinSeat()
        var o = load(credits2File)
        var m = (o["c"] as? [String: [String: Any]]) ?? [:]
        let now = Date().timeIntervalSince1970
        guard !m.isEmpty, 3600 <= now - ((o["at"] as? NSNumber)?.doubleValue ?? 0) else { return }
        for (id, c) in m {
            guard let from = c["f"] as? String, let coins = (c["n"] as? NSNumber)?.intValue, let conv = c["p"] as? String,
                  let door = chainDoor(from) else { m[id] = nil; continue }
            let f = await ask(door + "/tx-settle", ["send": id])
            guard let book = seat.book else { return }   // the credits' file stays in its person's folder
            guard f.code == 200, (f.obj?["state"] as? String) == "refund" else { continue }
            if book.holds(.send, gonePrefix + id) || book.retake(coins, to: conv, ref: gonePrefix + id) { m[id] = nil }
            MontanaTrace.mark("coin_v3", "credit gone coins=\(coins) id=\(id.prefix(12))")
        }
        o["c"] = m; o["at"] = now
        save(credits2File, o)
    }
}

// MARK: - the phone's copy of the network's coin chains (COIN-TX-V3 section 6)
/// EVERY PHONE THAT KEEPS A COPY IS A NODE OF THE COIN CHAINS (the author's words 11.10.2026 19:5x UTC: "the core and the nodes are
/// every device ... agreeing to keep a copy they keep a copy of the chain of time of the coins"; 20:3x: "check as the critic that
/// globally on every device the node is with the new build"). With the person's consent to keep for others (MTKeeping.others) the
/// phone pulls what each chain node took, verifies every signature with the core, folds every chain by the nodes' own rules,
/// computes the root of the newest checkpoint itself and signs it with the seed's coin key; the nodes keep the signature and the
/// Explorer counts it in the quorum. The whole network's chains, never only the correspondents': a holder's signature must not say
/// whose chains it cares about. The diary says what this phone holds (coin_replica), never whose chains.
enum MTCoinReplica {
    struct Row: Codable { let id: String; let rec: String; let at: Int64; let node: String }
    /// at: the moment of the last round, kept with the rows -- a process a push woke is born with nothing in memory. known: the
    /// names of the rows whose signature verified here once.
    struct Held: Codable { var seq: [String: Int] = [:]; var rows: [Row] = []; var at: Double? = nil; var known: [String]? = nil }
    typealias St = MTCoinChainRules.St
    typealias SendInfo = MTCoinChainRules.SendInfo
    @MainActor private static var running = false
    @MainActor private static var ranAt: TimeInterval = 0
    private static var url: URL? { MTTimeChainPlace.dir()?.appendingPathComponent("coin-replica.json") }
    private static func load() -> Held {
        guard let u = url, let d = try? Data(contentsOf: u), let h = try? JSONDecoder().decode(Held.self, from: d) else { return Held() }
        return h
    }
    private static func save(_ h: Held) {
        guard let u = url, let d = try? JSONEncoder().encode(h) else { return }
        MTDiskDoor.write(d, to: u, "coin-replica", options: .atomic)
    }
    nonisolated private static func bytes(_ s: String) -> Data? { MTCoinChainRules.bytes(s) }
    /// One record folded onto its key's state by the chain's rules (MTCoinChainRules.step, the nodes' _tx_step).
    nonisolated static func step(_ s: St, _ p: MTCoinTx.Record, _ at: Int64, _ sends: [String: SendInfo], _ settled: Set<String>) -> (next: St?, wait: Bool) {
        MTCoinChainRules.step(s, MTCoinChainRules.Rec(id: p.id, version: p.version, kind: p.kind, amount: Int64(p.coins), from: p.from, to: p.to, ref: p.ref,
                                            a: p.a, b: p.b), at, sends, settled)
    }
    struct Folded { var keys = 0; var records = 0; var root = ""; var bad = 0; var waiting = 0; var mine: St?; var verified = Set<String>() }
    /// Every chain folded from its first record in its own order (prev), a RECV after the SEND it settles; then the root of the
    /// checkpoint T exactly as the node computes it (V3 section 6): for every key in ascending from, its last record and its count at T.
    nonisolated static func fold(_ rows: [Row], at T: Int64, me: String? = nil, known: Set<String> = []) -> Folded {
        var out = Folded()
        var byPrev: [String: [String: MTCoinTx.Record]] = [:]
        var atOf: [String: Int64] = [:]
        var seen = Set<String>()
        for row in rows where !seen.contains(row.id) {
            seen.insert(row.id)
            guard let d = Data(base64Encoded: row.rec), let r = MTCoinTx.read(d, known: known.contains(row.id)), r.id == row.id else { out.bad += 1; continue }
            out.verified.insert(r.id)
            if r.version == 1 { continue }   // a version 1 row stands on no chain
            guard MTCoinTx.chainNode(of: r.from) == row.node else { out.bad += 1; continue }   // a node serves only its own chains
            byPrev[r.from, default: [:]][r.prev] = r
            atOf[r.id] = row.at
        }
        var st: [String: St] = [:], sends: [String: SendInfo] = [:], settled = Set<String>(), broken = Set<String>()
        var order: [String: [String]] = [:]
        var moved = true
        while moved {
            moved = false
            for (from, chain) in byPrev where !broken.contains(from) {
                var s = st[from] ?? St()
                while let r = chain[s.head] {
                    let at = atOf[r.id] ?? 0
                    let next = step(s, r, at, sends, settled)
                    if next.wait { break }
                    guard let n = next.next else { broken.insert(from); out.bad += 1; break }
                    if r.version == 3, r.kind == MTCoinTx.Kind3.send.rawValue {
                        sends[r.id] = SendInfo(from: from, amount: Int64(r.coins), at: at, to: r.to, dec: Int64(r.a))
                    }
                    if r.version == 2, let d = MTCoinChainRules.v2Spent(s, amount: Int64(r.coins)) {
                        sends[r.id] = SendInfo(from: from, amount: Int64(r.coins), at: at, to: Data(count: 32), dec: d)
                    }
                    if r.version == 3, r.kind == MTCoinTx.Kind3.recv.rawValue || r.kind == MTCoinTx.Kind3.refund.rawValue { settled.insert(r.ref) }
                    order[from, default: []].append(r.id)
                    s = n; moved = true
                }
                st[from] = s
            }
        }
        for (from, chain) in byPrev where !broken.contains(from) { if chain[st[from]?.head ?? MTCoinChainRules.zero] != nil { out.waiting += 1 } }
        if let me, !broken.contains(me) { out.mine = st[me] }
        var h = SHA256()
        h.update(data: Data("mt-coin-root-v1".utf8))
        for from in order.keys.sorted() {
            let ids = (order[from] ?? []).filter { id in (atOf[id] ?? Int64.max) <= T }
            guard let last = ids.last, let f = bytes(from), let l = bytes(last) else { continue }
            var c = UInt64(ids.count).littleEndian
            h.update(data: f); h.update(data: l); h.update(data: withUnsafeBytes(of: &c) { p in Data(p) })
            out.keys += 1; out.records += ids.count
        }
        out.root = MTCoinTx.hex(Data(h.finalize()))
        return out
    }
    /// One round: what each chain node took since the last round, the whole fold, the root of the nodes' newest checkpoint computed
    /// here and signed with the seed's coin key at both nodes. Once in ten minutes at most, only with the consent to keep for others.
    @MainActor static func run(why: String) async {
        guard MTKeeping.others, !running, 600 <= Date().timeIntervalSince1970 - ranAt, let k = MTCoinTx.keys() else { return }
        running = true
        ranAt = Date().timeIntervalSince1970
        defer { running = false }
        // THE BOOK IS READ AND WRITTEN OFF THE SCREEN'S THREAD (the author's words 18.10.2026 11:3x-11:4x UTC: «the chats lag»; «as
        // the critic, find the cause of all the lags»): the whole network's rows, decoded and encoded on the main thread every ten
        // minutes -- T1 on 2241, 11:38:36Z, a frame of the chat list held 438 ms in JSONEncoder under MTCoinReplica.save.
        var held = await Task.detached(priority: .utility) { load() }.value
        // ONCE IN TEN MINUTES ACROSS PROCESSES (23.10.2026, the author's words 09:16 UTC: «I quit Montana on the Mac, and it hangs and
        // starts by itself»): ranAt lives in memory, and every process a push woke was born with it at zero -- each wake pulled and
        // folded the whole network again, a signature verified per row (sample of a wake on the Mac 09:32:48: 5.6 s of 25 under
        // MTCoinReplica.fold, MontanaPQ.verify on top). The round's moment stands in the file it folds.
        guard 600 <= Date().timeIntervalSince1970 - (held.at ?? 0) else { return }
        held.at = Date().timeIntervalSince1970
        var pulled = 0
        for n in MTCoinTx.chainNodes {
            let door = "https://" + n.host + "/pushwake"
            var since = held.seq[n.name] ?? 0
            for _ in 0..<64 {
                let a = await MTCoinTx.post(door + "/tx-since", ["since": since])
                guard a.code == 200, let txs = a.obj?["txs"] as? [[String: Any]] else { break }
                for x in txs {
                    guard let id = x["id"] as? String, let rec = x["rec"] as? String, let seq = (x["seq"] as? NSNumber)?.intValue else { continue }
                    held.rows.append(Row(id: id, rec: rec, at: (x["at"] as? NSNumber)?.int64Value ?? 0, node: n.name))
                    since = max(since, seq); pulled += 1
                }
                held.seq[n.name] = since
                if txs.count < 512 { break }
            }
        }
        let kept = held
        await Task.detached(priority: .utility) { save(kept) }.value
        let me = MTCoinTx.keyTag(k.pk)
        guard let door = MTCoinTx.chainDoor(me) else { return }
        let r = await MTCoinTx.post(door + "/tx-root", [:])
        guard r.code == 200, let T = (r.obj?["at"] as? NSNumber)?.int64Value, let nodeRoot = r.obj?["root"] as? String else {
            MontanaTrace.mark("coin_replica", "why=\(why) pulled=\(pulled) rows=\(held.rows.count) no checkpoint code=\(r.code)")
            return
        }
        let rows = held.rows
        let known = Set(held.known ?? [])
        let f = await Task.detached(priority: .utility) { fold(rows, at: T, me: me, known: known) }.value
        if f.verified != known {
            held.known = f.verified.sorted()
            let verified = held
            await Task.detached(priority: .utility) { save(verified) }.value
        }
        // the person's own chain as this copy folded it: the wallet's split hears it before the node's word (MTCoinSplit)
        if f.bad == 0, let mine = f.mine { MTCoinSplit.shared.heard(proven: mine.proven, declared: mine.declared, opened: mine.v3, fromCopy: true, height: mine.height, second: T, mintEnd: mine.mintEnd) }
        var signed = 0
        if f.bad == 0, 0 < f.keys, let root = bytes(f.root) {
            var t = UInt64(T).littleEndian
            let msg = Data("mt-coin-root-sig-v1".utf8) + withUnsafeBytes(of: &t) { p in Data(p) } + root
            if let sig = MontanaPQ.sign(seckey: k.sk, message: msg) {
                for n in MTCoinTx.chainNodes {
                    let a = await MTCoinTx.post("https://" + n.host + "/pushwake/tx-root-sign",
                                                ["pk": k.pk.base64EncodedString(), "at": T, "root": f.root, "sig": sig.base64EncodedString()])
                    if a.code == 200 { signed += 1 }
                }
            }
        }
        MontanaTrace.mark("coin_replica", "why=\(why) keys=\(f.keys) records=\(f.records) pulled=\(pulled) bad=\(f.bad) waiting=\(f.waiting) T=\(T) root=\(f.root.prefix(12)) same=\(f.root == nodeRoot ? 1 : 0) signed=\(signed)")
    }
}

extension MTCoinTx {
    /// A node's answer for a reader outside this type (the phone's copy of the chains): the code and the body.
    static func post(_ url: String, _ body: [String: Any]) async -> (code: Int, obj: [String: Any]?) {
        let a = await ask(url, body)
        return (a.code, a.obj)
    }
}
