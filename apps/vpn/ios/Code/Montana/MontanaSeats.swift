import Foundation
import SwiftUI
import UIKit

// ════════════════════════════════════════════════════════════
// THE SEATS OF MONTANA ON ONE PHONE (the second identity checklist, 1.1 to 1.5; the author's word 29.09: «Montana creates
// a second identity with the possibility to switch»).
//
// One phone held one person: MontanaSeed.setActive keeps one seed, and the boundary that let a second one in wiped the
// first one's history. A seat is a person on this phone. The person seated now lives where every owner already reads;
// the others wait on the shelf, each in a folder of its own and one record of the device-only keychain. The person's
// layer is named at the birth of every key (SeedScope: dataKeys, dataPrefixes, seatKeys, seatPrefixes, seatKeychain,
// seatFolders), so a move sweeps nothing: it carries exactly what the classes name, and the copy's guard refuses a key
// named nowhere.
//
// A MOVE IS ONE ROAD (move): the screen steps aside and the correspondence store steps down (ChatStore.retire), a settle
// lets every write of the person leaving land in that person's own layer, the layer is parked with a read back, the layer
// is cleared, the next person is lifted, and a new store is born reading the lifted history as a launch does. Every
// stage is written in the book before it runs; a launch after a broken move finishes it (launch). Nothing is deleted: a
// folder found where a lifted one must stand is set aside on the shelf of the person who left (seat_stray).
// ════════════════════════════════════════════════════════════
final class MTSeats: ObservableObject {
    static let shared = MTSeats()
    @Published private(set) var moving = false
    /// The identifier of the person who is seated now.  The root uses this as the identity of
    /// its stateful tree: after a lift, no @StateObject from the person who left may be mounted
    /// again over the lifted person's folders and vault.
    @Published private(set) var activeId: String?
    @Published private(set) var parked: [Seat] = []      // the persons on the shelf, for the drawer's faces
    @Published private(set) var canReturn = false        // the layer is empty and somebody waits on the shelf
    @Published private(set) var adding = false           // the first screen stands to make a second person
    @Published private(set) var addingByPhone = false    // ... and the door tapped was the number's: the road stands while adding (06.10)
    private var montanaRoad = false                      // the first screen after making room opens on the Montana road
    private var phoneRoad = false                        // ... or on the number's road (the Business's door, 06.10)
    private init() { refresh() }

    struct Seat: Codable, Equatable, Identifiable {
        let id: String
        var born: Double
        var name: String
        var glyph: String
    }
    struct Step: Codable, Equatable {
        var from: String?
        var to: String?
        var stage: String      // settle, park, clear, lift
    }
    struct Book: Codable {
        var active: String?
        var last: String?
        var seats: [Seat]
        var step: Step?
    }
    private struct Record: Codable {
        let words: String
        var chain: [String: Data]
    }

    // ── the book and the records: the device-only keychain, the class the active seed wears ──

    private static let seatBookKey = "mt.seats"
    private static func seatRecordName(_ id: String) -> String { "mt.seat." + id }

    static func book() -> Book {
        guard let d = E2EKeychain.getDeviceOnly(seatBookKey), let b = try? JSONDecoder().decode(Book.self, from: d) else {
            return Book(active: nil, last: nil, seats: [], step: nil)
        }
        return b
    }
    @discardableResult
    private static func write(_ b: Book) -> Bool {
        guard let d = try? JSONEncoder().encode(b) else { return false }
        E2EKeychain.setDeviceOnly(seatBookKey, d)
        return E2EKeychain.getDeviceOnly(seatBookKey) == d
    }
    private static func stage(_ name: String) {
        var b = book()
        b.step?.stage = name
        write(b)
    }
    private static func record(_ id: String) -> Record? {
        guard let d = E2EKeychain.getDeviceOnly(seatRecordName(id)) else { return nil }
        return try? JSONDecoder().decode(Record.self, from: d)
    }
    /// Somebody waits on the shelf of this phone: the device key that seals their values must stand.
    static var anyParked: Bool {
        let b = book()
        return b.seats.contains { $0.id != b.active }
    }

    /// The published state the drawer and the root read, from the book.
    func refresh() {
        let b = Self.book()
        activeId = b.active
        parked = b.seats.filter { $0.id != b.active }
        canReturn = !MontanaSeed.hasSeed && !parked.isEmpty
    }

    // ── the places ──

    static var seatsRoot: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Montana", isDirectory: true).appendingPathComponent("Seats", isDirectory: true)
    }
    private static func seatDir(_ id: String) -> URL { seatsRoot.appendingPathComponent(id, isDirectory: true) }
    /// A folder of the person's layer, by the name the copy's guard gives it: the root and the path under it.

    private static func base(_ root: Substring) -> URL? {
        let fm = FileManager.default
        if root == "GROUP" { return fm.containerURL(forSecurityApplicationGroupIdentifier: MontanaContour.appGroup) }
        if root == "DOC" { return fm.urls(for: .documentDirectory, in: .userDomainMask).first }
        if root == "AS" { return fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first }
        return nil
    }


    private static func place(of folder: String) -> URL? {
        let parts = folder.split(separator: ":", maxSplits: 1)
        guard parts.count == 2, let root = base(parts[0]) else { return nil }
        return root.appendingPathComponent(String(parts[1]), isDirectory: true)
    }
    private static func shelf(of folder: String, in id: String) -> URL {
        seatDir(id).appendingPathComponent("folders", isDirectory: true)
            .appendingPathComponent(folder.replacingOccurrences(of: ":", with: "_").replacingOccurrences(of: "/", with: "_"), isDirectory: true)
    }
    /// The place a folder of a parked person waits on their shelf -- for an owner that lays a person's files there (MTCoinPlace).
    static func shelf(folder: String, seat id: String) -> URL { shelf(of: folder, in: id) }
    /// Where a folder found standing at a lifted one's place goes: the shelf of the person who left, or the phone's own
    /// shelf when nobody left (a seat that stood empty).
    private static func strays(of from: String?) -> URL {
        (from.map { seatDir($0) } ?? seatsRoot).appendingPathComponent("strays", isDirectory: true)
    }
    private static func valuesFile(_ id: String) -> URL { seatDir(id).appendingPathComponent("person.plist") }
    private static func faceFile(_ id: String) -> URL { seatDir(id).appendingPathComponent("face") }

    /// The face of a person on the shelf, for the drawer.
    static func face(_ id: String) -> UIImage? { (try? Data(contentsOf: faceFile(id))).flatMap { UIImage(data: $0) } }

    /// Whether a value of the settings store is the person's: the classes SeedScope names, and nothing else.
    static func layerHolds(_ k: String) -> Bool {
        if SeedScope.dataKeys.contains(k) || SeedScope.seatKeys.contains(k) || SeedScope.boundaryKeys.contains(k) { return true }
        if SeedScope.legacyKeys.contains(k) || SeedScope.legacyEntryKeys.contains(k) { return true }
        return (SeedScope.dataPrefixes + SeedScope.seatPrefixes + SeedScope.legacyPrefixes).contains { k.hasPrefix($0) }
    }

    /// A folder moved to where it must stand. What already stands there empty is an owner's fresh drawing and nothing of
    /// anybody's; what stands there full was written after the park by the person who left, and it is theirs: it goes to
    /// their shelf, never under the next person and never away.
    private static func put(_ src: URL, at dst: URL, strays: URL?) -> Bool {
        let fm = FileManager.default
        if fm.fileExists(atPath: dst.path) {
            let inside = (try? fm.contentsOfDirectory(atPath: dst.path)) ?? []
            if inside.isEmpty {
                try? fm.removeItem(at: dst)
            } else if let strays {
                try? fm.createDirectory(at: strays, withIntermediateDirectories: true)
                let aside = strays.appendingPathComponent(dst.lastPathComponent + "-" + String(Int(Date().timeIntervalSince1970 * 1000)))
                guard (try? fm.moveItem(at: dst, to: aside)) != nil else { return false }
                MontanaP2PTrace.mark("seat_stray", "folder=" + dst.lastPathComponent + " n=" + String(inside.count))
            } else {
                return false
            }
        }
        try? fm.createDirectory(at: dst.deletingLastPathComponent(), withIntermediateDirectories: true)
        return (try? fm.moveItem(at: src, to: dst)) != nil
    }

    // ── park, clear, lift ──

    /// The person seated now goes to the shelf: the values with a read back, the keychain items and the seed with a read
    /// back, the folders by one rename each, the name and the face for the drawer. A refusal folds back what moved.
    private static func park(_ id: String) -> Bool {
        let t0 = Date()
        let fm = FileManager.default
        let dir = seatDir(id)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let ud = UserDefaults.standard
        let domain = ud.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "") ?? [:]
        let layer = domain.filter { layerHolds($0.key) }
        guard let plist = try? PropertyListSerialization.data(fromPropertyList: layer, format: .binary, options: 0),
              (try? plist.write(to: valuesFile(id), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])) != nil,
              let back = try? Data(contentsOf: valuesFile(id)), back == plist else {
            MontanaP2PTrace.mark("seat_park", "REFUSED values id=" + id)
            return false
        }
        var chain: [String: Data] = [:]
        for k in SeedScope.seatKeychain { if let d = MontanaKeychain.get(k) { chain[k] = d } }
        guard let words = MontanaSeed.mnemonic, let rec = try? JSONEncoder().encode(Record(words: words, chain: chain)) else {
            MontanaP2PTrace.mark("seat_park", "REFUSED no seed id=" + id)
            return false
        }
        E2EKeychain.setDeviceOnly(seatRecordName(id), rec)
        guard E2EKeychain.getDeviceOnly(seatRecordName(id)) == rec else {
            MontanaP2PTrace.mark("seat_park", "REFUSED record id=" + id)
            return false
        }
        var moved: [String] = []
        for f in SeedScope.seatFolders {
            guard let src = place(of: f), fm.fileExists(atPath: src.path) else { continue }
            if put(src, at: shelf(of: f, in: id), strays: dir.appendingPathComponent("strays", isDirectory: true)) {
                moved.append(f)
            } else {
                for m in moved { if let p = place(of: m) { _ = put(shelf(of: m, in: id), at: p, strays: nil) } }
                MontanaP2PTrace.mark("seat_park", "REFUSED folder=" + f + " id=" + id)
                return false
            }
        }
        let face = ud.data(forKey: "avatarData") ?? Data()
        try? face.write(to: faceFile(id), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        var b = book()
        let name = [ud.string(forKey: "userName"), ud.string(forKey: "userLastName")].compactMap { $0 }
            .joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        if let i = b.seats.firstIndex(where: { $0.id == id }) {
            b.seats[i].name = name
            b.seats[i].glyph = E2E.myFaceGlyph()
        }
        write(b)
        MontanaP2PTrace.mark("seat_park", "id=" + id + " keys=" + String(layer.count) + " chain=" + String(chain.count) +
                             " folders=" + String(moved.count) + " ms=" + String(Int(Date().timeIntervalSince(t0) * 1000)))
        return true
    }

    /// A launch found a park that did not finish: whatever reached the shelf goes back; the layer was never cleared.
    private static func unpark(_ id: String) {
        for f in SeedScope.seatFolders {
            let parked = shelf(of: f, in: id)
            guard FileManager.default.fileExists(atPath: parked.path), let p = place(of: f) else { continue }
            _ = put(parked, at: p, strays: seatDir(id).appendingPathComponent("strays", isDirectory: true))
        }
    }

    /// The layer's store is empty: the values, the keychain items, the seed. Nothing here touches memory.
    private static func clearStore() {
        let ud = UserDefaults.standard
        for k in ud.dictionaryRepresentation().keys where layerHolds(k) { ud.removeObject(forKey: k) }
        for k in SeedScope.seatKeychain { MontanaKeychain.delete(k) }
        MontanaSeed.clear()
        MontanaLocalVault.commit()
    }
    /// Every owner that holds a value of the person who left in memory lets it go: the same doors SeedScope.forget uses.
    private static func clearMemory() {
        E2E.forgetDeviceTag()
        MTPipeBook.forgetAll()
        MontanaArchive.forgetKeys()
        MontanaQueueKeys.forgetMasterSeed()
        MontanaOverlayKey.forget()
        MontanaNodeKem.forget()
        MontanaP2PNode.shared.forgetMyRef()
        MontanaCard.wipe()
        MTOutbox.wipe()
        MontanaNotify.forgetAllSuggestions()
        NotificationCenter.default.post(name: .montanaSeedForgotten, object: nil)
        SeedScope.reread(restored: false)
        Task { @MainActor in MTCoinBook.reread() }   // the coins of the person who left leave memory with them (04.10)
    }

    /// A person on the shelf takes the seat: the checks first (the record and its words, the values), then the folders,
    /// the values, the keychain items and the seed. The seed's boundary rides the lifted values.
    private static func liftStore(_ id: String, strays: URL?) -> Bool {
        let t0 = Date()
        guard let rec = record(id), !rec.words.isEmpty,
              let plist = try? Data(contentsOf: valuesFile(id)),
              let layer = (try? PropertyListSerialization.propertyList(from: plist, options: [], format: nil)) as? [String: Any] else {
            MontanaP2PTrace.mark("seat_lift", "REFUSED id=" + id)
            return false
        }
        var moved = 0
        for f in SeedScope.seatFolders {
            let parked = shelf(of: f, in: id)
            guard FileManager.default.fileExists(atPath: parked.path), let p = place(of: f) else { continue }
            if put(parked, at: p, strays: strays) { moved += 1 }
        }
        let ud = UserDefaults.standard
        for (k, v) in layer { ud.set(v, forKey: k) }
        for (k, d) in rec.chain { MontanaKeychain.set(k, d) }
        guard MontanaSeed.setActive(mnemonic: rec.words) else {
            MontanaP2PTrace.mark("seat_lift", "REFUSED seed id=" + id)
            return false
        }
        MontanaLocalVault.commit()
        var b = book()
        b.active = id
        write(b)
        MontanaP2PTrace.mark("seat_lift", "id=" + id + " keys=" + String(layer.count) + " chain=" + String(rec.chain.count) +
                             " folders=" + String(moved) + " ms=" + String(Int(Date().timeIntervalSince(t0) * 1000)))
        return true
    }
    /// The lifted person's memory: every owner reads the store again, the node and the wake door learn who is seated. The
    /// word of a forgotten seed is NOT spoken here: a store of the person who left that still lived would hear it and drop
    /// the history file and the rows' journal, which are the lifted person's now.
    private static func liftMemory() {
        E2E.forgetDeviceTag()
        SeedScope.reread(restored: false)
        MTBoard.shared.reread()   // the wall loads on the forgotten seed's word, which is not spoken here: it reads the lifted wall
        Task { @MainActor in MTCoinBook.reread() }   // the lifted person's own coins, never the book of the one who left (04.10)
        MontanaAppleID.publish()
        NotificationCenter.default.post(name: .montanaSeedOpened, object: nil)
        MontanaWakePush.registerConvs()
        MontanaP2PNode.shared.reconnectNow()
        landShelf()   // what the shelf received while the person waited lands as a pickup's rows (MTShelfPost)
    }

    /// An empty place of a folder wears what the folder it replaces wore (kept out of the device's backup or not).
    private static func drawEmptyPlaces(like id: String?) {
        let fm = FileManager.default
        for f in SeedScope.seatFolders {
            guard let p = place(of: f), !fm.fileExists(atPath: p.path) else { continue }
            try? fm.createDirectory(at: p, withIntermediateDirectories: true)
            guard let id, let v = try? shelf(of: f, in: id).resourceValues(forKeys: [.isExcludedFromBackupKey]),
                  v.isExcludedFromBackup == true else { continue }
            var q = p
            var rv = URLResourceValues()
            rv.isExcludedFromBackup = true
            try? q.setResourceValues(rv)
        }
    }

    // ── the shelf served (MTShelfPost): read and written by this device's key, never through the person seated ──

    /// THE SHELF'S ONE QUEUE: every file the shelf's service writes for a person -- their inbox on the shelf and the pipes they
    /// were met by -- is written on it, after asking that no move runs and the person still waits; the person seated lands
    /// their own shelf inbox on it too, at the lift and at every pickup, so a row filed in the instant of a move is never left.
    /// Nothing waits on a lock (tools/mt-lock-check.py): the queue orders the files, and the main thread never waits on it.
    private static let shelfIO = DispatchQueue(label: "montana.seats.shelf", qos: .utility)
    /// The persons waiting on the shelf, as their own stores keep them; none while a move runs.
    static func shelfPeople() -> [MTShelfPost.Person] {
        let b = book()
        guard b.step == nil else { return [] }
        return b.seats.filter { $0.id != b.active }.compactMap { shelfPerson($0) }
    }
    private static func shelfValues(_ id: String) -> [String: Any]? {
        guard let plist = try? Data(contentsOf: valuesFile(id)) else { return nil }
        return (try? PropertyListSerialization.propertyList(from: plist, options: [], format: nil)) as? [String: Any]
    }
    /// A sealed value of a person's store opened by this device's key: their own name for the value is its seal's binding.
    private static func shelfOpen(_ values: [String: Any], _ key: String) -> Data? {
        guard let raw = values[key] as? Data else { return nil }
        return MontanaLocalVault.open(raw, Data(key.utf8)) ?? MontanaLocalVault.open(raw, Data())
    }
    private static func shelfBook(_ values: [String: Any], _ key: String) -> [String: Data] {
        shelfOpen(values, key).flatMap { try? JSONDecoder().decode([String: Data].self, from: $0) } ?? [:]
    }
    private static func shelfPerson(_ seat: Seat) -> MTShelfPost.Person? {
        guard let rec = record(seat.id), !rec.words.isEmpty, let values = shelfValues(seat.id) else { return nil }
        let twin = shelfOpen(values, "mt.twin.ref").flatMap { String(data: $0, encoding: .utf8) } ?? ""
        return MTShelfPost.Person(id: seat.id, name: seat.name, glyph: seat.glyph, twin: twin, words: rec.words,
                                  pipes: shelfBook(values, "pipeSecrets").merging(shelfSealed(metFile(seat.id), metBinding)) { a, _ in a },
                                  invites: shelfBook(values, "rdvCards").merging(shelfBook(values, "rdvPermanent")) { a, _ in a },
                                  cardKeys: shelfBook(values, "cardKeys"),
                                  outbox: rec.chain["mt.outbox.key"].flatMap { k in
                                      (try? Data(contentsOf: shelf(of: "GROUP:delivery", in: seat.id).appendingPathComponent("pending.sealed")))
                                          .flatMap { MTOutbox.open($0, key: k) } } ?? [],
                                  firsts: Set(shelfBook(values, "pipeFirstCiphertexts").keys))
    }
    /// The files the shelf keeps beside a person's store, sealed under this device's key: the rows they received while they
    /// waited, and the pipes their card was met by (born in their own book by the landing door at their lift, which seals the
    /// pipe under their seed -- MTPipeBook.establish).
    private static func inboxFile(_ id: String) -> URL { seatDir(id).appendingPathComponent("inbox") }
    private static func metFile(_ id: String) -> URL { seatDir(id).appendingPathComponent("met") }
    private static let inboxBinding = Data("mt.seat.inbox".utf8)
    private static let metBinding = Data("mt.seat.met".utf8)
    private static func shelfSealed<T: Decodable>(_ url: URL, _ binding: Data, as: T.Type) -> T? {
        guard let raw = try? Data(contentsOf: url), let plain = MontanaLocalVault.open(raw, binding) else { return nil }
        return try? JSONDecoder().decode(T.self, from: plain)
    }
    private static func shelfSealed(_ url: URL, _ binding: Data) -> [String: Data] { shelfSealed(url, binding, as: [String: Data].self) ?? [:] }
    private static func shelfInbox(_ id: String) -> [[String: String]] { shelfSealed(inboxFile(id), inboxBinding, as: [[String: String]].self) ?? [] }
    private static func shelfSeal<T: Encodable>(_ value: T, _ url: URL, _ binding: Data) -> Bool {
        guard let plain = try? JSONEncoder().encode(value), let sealed = MontanaLocalVault.seal(plain, binding) else { return false }
        return (try? sealed.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])) != nil
    }
    /// Rows a person on the shelf received go into their inbox on the shelf. Refused while a move runs or once the person is
    /// seated: the row then stays on the node for the next pickup.
    static func fileShelf(_ id: String, rows: [[String: String]]) -> Bool {
        // MAIN-SAFE-SYNC: called only from the shelf's own detached task (MTShelfPost.serve), never from the main thread; the
        // queue holds file writes of the shelf alone, and the row must be on disk before the node is told to drop it.
        shelfIO.sync {
            let b = book()
            guard b.step == nil, b.active != id else { return false }
            var arr = shelfInbox(id)
            var have = Set(arr.compactMap { $0["m"] })
            for r in rows where have.insert(r["m"] ?? "").inserted { arr.append(r.filter { !$0.value.isEmpty }) }
            return shelfSeal(arr, inboxFile(id), inboxBinding)
        }
    }
    /// A pipe a person on the shelf was met by, kept beside their store until their lift.
    static func meetOnShelf(_ id: String, ref: String, secret: Data) -> Bool {
        // MAIN-SAFE-SYNC: called only from the shelf's own detached task (MTShelfPost.answer), never from the main thread.
        shelfIO.sync {
            let b = book()
            guard b.step == nil, b.active != id else { return false }
            var m = shelfSealed(metFile(id), metBinding)
            if let have = m[ref] { return have == secret }
            m[ref] = secret
            return shelfSeal(m, metFile(id), metBinding)
        }
    }
    /// THE PERSON SEATED TAKES WHAT THE SHELF RECEIVED FOR THEM: the rows go into their inbox as a pickup's rows (the landing
    /// door opens them), and only then leave the shelf's file. Asked at the lift and at every pickup of the person seated.
    static func landShelf() {
        shelfIO.async {
            guard let id = book().active else { return }
            let rows = shelfInbox(id)
            guard !rows.isEmpty else { return }
            DispatchQueue.main.async {
                MontanaWakePush.stashFromShelf(rows)
                MontanaP2PTrace.mark("shelf_land", "seat=" + id + " rows=" + String(rows.count))
                let landed = Set(rows.compactMap { $0["m"] })
                shelfIO.async {
                    let rest = shelfInbox(id).filter { !landed.contains($0["m"] ?? "") }
                    if rest.isEmpty { try? FileManager.default.removeItem(at: inboxFile(id)) } else { _ = shelfSeal(rest, inboxFile(id), inboxBinding) }
                }
            }
        }
    }

    // ── the roads ──

    /// The person seated before seats were used takes a seat of their own at their first move.
    private static func seatForActive(_ b: inout Book) -> String {
        if let a = b.active { return a }
        let id = newId()
        b.seats.append(Seat(id: id, born: Date().timeIntervalSince1970, name: "", glyph: ""))
        b.active = id
        return id
    }
    /// A seat's name: a folder of this phone and a record's name, drawn by the core's own source.
    private static func newId() -> String {
        montanaRandom(4).map { String(format: "%02x", $0) }.joined()
    }

    /// The drawer's face of a person on the shelf.
    func switchTo(_ id: String) {
        let b = Self.book()
        guard !moving, b.active != id, b.seats.contains(where: { $0.id == id }) else { return }
        move(to: id)
    }
    /// The Montana door beside a person already seated: the seat is emptied, and the first screen stands on the Montana road --
    /// or on the number's road, when the door of the number was the one tapped (06.10).
    func makeRoom(phone: Bool = false) {
        guard !moving, MontanaSeed.hasSeed else { return }
        montanaRoad = !phone
        phoneRoad = phone
        addingByPhone = phone
        adding = true
        move(to: nil)
    }
    /// The first screen closed: a person was made.
    func doneAdding() { adding = false; addingByPhone = false }
    /// The first screen asks once whether it was opened to make a person (the Montana road) rather than to choose a door.
    func takeMontanaRoad() -> Bool {
        defer { montanaRoad = false }
        return montanaRoad
    }
    /// The same question for the number's road: the door of the number was tapped beside a person already seated.
    func takePhoneRoad() -> Bool {
        defer { phoneRoad = false }
        return phoneRoad
    }
    /// The first screen's cross: the person who waited on the shelf last comes back.
    func returnToLast() {
        guard !moving, !MontanaSeed.hasSeed else { return }
        let b = Self.book()
        guard let id = b.last.flatMap({ l in b.seats.first { $0.id == l }?.id }) ?? b.seats.first?.id else { return }
        adding = false; addingByPhone = false
        move(to: id)
    }

    /// THE MOVE (1.3). From an empty seat there is nobody to settle or park; to an empty seat nobody is lifted.
    private func move(to target: String?) {
        moving = true
        var b = Self.book()
        let from: String? = MontanaSeed.hasSeed ? Self.seatForActive(&b) : nil
        b.step = Step(from: from, to: target, stage: "settle")
        if let from { b.last = from }
        Self.write(b)
        let t0 = Date()
        MontanaP2PTrace.mark("seat_move", "begin from=" + (from ?? "-") + " to=" + (target ?? "-"))
        weak var old: ChatStore?   // the store of the person leaving, watched without being held
        old = ChatStore.live
        old?.retire()
        MTBoard.shared.flush()
        MontanaLocalVault.commit()
        let earliest = Date().addingTimeInterval(from == nil ? 0 : 1.2)
        let latest = Date().addingTimeInterval(4)
        func settled() {
            // The store of the person leaving dies with the screen; while it lives, what it writes is still that person's.
            if Date() < earliest || (old != nil && Date() < latest) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { settled() }
                return
            }
            if old != nil { MontanaP2PTrace.mark("seat_move", "the store of the person leaving still lives") }
            MontanaCard.afterWrites { self.parkThenLift(from: from, to: target, t0: t0) }
        }
        settled()
    }
    private func parkThenLift(from: String?, to target: String?, t0: Date) {
        let ground = target == nil && from != nil ? MTWallpaper.carry() : nil   // a seat emptied for a new person keeps the cover (03.10)
        if let from {
            // The coins of the person leaving are on disk in their own folder before it moves (the coin audit's fourth point).
            let keep = { MainActor.assumeIsolated { MTLocalCoinLedger.shared.writeWhole() } }
            // MAIN-SAFE-SYNC: the main thread runs keep itself; only a caller off it waits, on main, which waits on nobody here.
            if Thread.isMainThread { keep() } else { DispatchQueue.main.sync(execute: keep) }
            Self.stage("park")
            guard Self.park(from) else {
                var b = Self.book(); b.step = nil; Self.write(b)
                finish(t0, "refused")
                return
            }
        }
        Self.stage("clear")
        Self.clearStore()
        Self.clearMemory()
        MontanaCard.afterWrites {
            if let target {
                Self.stage("lift")
                if Self.liftStore(target, strays: Self.strays(of: from)) {
                    Self.liftMemory()
                } else if let from, Self.liftStore(from, strays: nil) {
                    Self.liftMemory()
                }
            } else {
                var b = Self.book(); b.active = nil; Self.write(b)
            }
            Self.drawEmptyPlaces(like: from)
            if let ground {
                MTWallpaper.wear(ground)
                MontanaP2PTrace.mark("seat_ground", "carried into the empty seat")
            }
            var b = Self.book(); b.step = nil; Self.write(b)
            self.finish(t0, "done")
        }
    }
    private func finish(_ t0: Date, _ word: String) {
        if word == "refused" { adding = false; montanaRoad = false; phoneRoad = false }   // the person stays seated: nothing to make room for
        refresh()
        moving = false
        MontanaP2PTrace.mark("seat_move", word + " active=" + (Self.book().active ?? "-") + " ms=" + String(Int(Date().timeIntervalSince(t0) * 1000)))
    }

    /// The one door into a person (MontanaSeed.enter) asks first: words of a person waiting on the shelf lift that seat,
    /// and no second copy of them is born. Only on an empty seat, where no store lives and nothing settles.
    static func lift(words: String) -> Bool {
        guard !MontanaSeed.hasSeed, ChatStore.live == nil else { return false }
        let b = book()
        guard let seat = b.seats.first(where: { $0.id != b.active && record($0.id)?.words == words }) else { return false }
        var w = b
        w.step = Step(from: nil, to: seat.id, stage: "lift")
        write(w)
        let ok = liftStore(seat.id, strays: strays(of: nil))
        if ok { liftMemory() }
        drawEmptyPlaces(like: nil)
        var e = book(); e.step = nil; write(e)
        DispatchQueue.main.async { shared.refresh() }
        return ok
    }
    /// A person born or opened on an empty seat of a phone that already has seats takes a seat of their own.
    static func born() {
        var b = book()
        guard !b.seats.isEmpty, b.active == nil, MontanaSeed.hasSeed else { return }
        _ = seatForActive(&b)
        write(b)
        MontanaP2PTrace.mark("seat_born", "id=" + (b.active ?? "-") + " seats=" + String(b.seats.count))
        DispatchQueue.main.async { shared.refresh() }
    }

    /// A LAUNCH AFTER A BROKEN MOVE (1.3): the stage the book names is finished before any owner is born.
    static func launch() {
        guard let s = book().step else { return }
        MontanaP2PTrace.mark("seat_resume", "stage=" + s.stage + " from=" + (s.from ?? "-") + " to=" + (s.to ?? "-"))
        switch s.stage {
        case "park":
            if let from = s.from { unpark(from) }
        case "clear", "lift":
            if s.stage == "clear" { clearStore() }
            if let to = s.to {
                if !liftStore(to, strays: strays(of: s.from)), let from = s.from {
                    _ = liftStore(from, strays: nil)
                }
            }
            drawEmptyPlaces(like: s.from)
        default:
            break
        }
        var e = book()
        if s.stage == "clear", s.to == nil { e.active = nil }
        e.step = nil
        write(e)
    }

    /// The person seated now is forgotten (SeedScope.forget) while others wait on the shelf: the seat leaves the book with
    /// its record, and what the person's folders still hold is set aside on the shelf, never under the next person.
    static func leaveForgotten() {
        var b = book()
        guard let id = b.active else { return }
        let aside = seatsRoot.appendingPathComponent("left-" + String(Int(Date().timeIntervalSince1970 * 1000)), isDirectory: true)
        for f in SeedScope.seatFolders {
            guard let p = place(of: f), FileManager.default.fileExists(atPath: p.path) else { continue }
            _ = put(p, at: aside.appendingPathComponent(f.replacingOccurrences(of: ":", with: "_").replacingOccurrences(of: "/", with: "_"), isDirectory: true), strays: nil)
        }
        E2EKeychain.delete(seatRecordName(id))
        b.seats.removeAll { $0.id == id }
        b.active = nil
        if b.last == id { b.last = b.seats.first?.id }
        write(b)
        drawEmptyPlaces(like: nil)
        MontanaP2PTrace.mark("seat_forgotten", "left=" + String(b.seats.count))
        DispatchQueue.main.async { shared.refresh() }
    }

    /// THE INSTALL BOUNDARY (E2ECore.swift, MontanaInstall): the keychain outlives the app, and a person who deleted it meant
    /// every person on it to be forgotten. The records and the book leave; the folders left with the app's container.
    static func forgetRecords() {
        let b = book()
        for s in b.seats { E2EKeychain.delete(seatRecordName(s.id)) }
        E2EKeychain.delete(seatBookKey)
    }
}


// ════════════════════════════════════════════════════════════
// THE PERSONS ON THE SHELF ARE ALIVE (the author's words 07.10.2026 19:1x-19:2x MSK: «so the extra accounts are dead until I enter
// them -- a critical error, and on our TimeChain it is solved already -- make the same one system by our constitution»; «carry it to
// the end and close the construction -- we are a decentralised ecosystem with a constitution of 13 points»). The constitution's
// sixth point: the phone is a full node, and a node serves every account it holds, seated or not -- the TimeChain's own answer, as
// the coin book rides the seed on the nodes (MTCoinVault) and lives without a device. A person on this phone's shelf is served so:
//   1. their post is read: every pickup of the person seated asks for one (MontanaWakePush.fetchBox), and the shelf's labels go
//      by the same pickup (MontanaWakePush.pickup); the rows go into the person's own inbox on the shelf (MTSeats.fileShelf), and
//      the landing door opens them at their lift as any row;
//   2. they answer: a first letter to their card is opened with their own card key and its pipe kept beside their store
//      (MTSeats.meetOnShelf); a letter of words or coins in hand is receipted under their own name and reference
//      (MTNodeWire.knockLetter) -- the sender sees it delivered;
//   3. their coins arrive: a coin letter credits their book on the nodes under their own seed (MTCoinVault.lay) by the letter's
//      wire name, the name the landing at their lift credits by -- one credit.
// Nothing of the person seated is read or written here: every key comes from the shelf (tools/mt-live-seats-check.py).
// ════════════════════════════════════════════════════════════
enum MTShelfPost {
    struct Person {
        let id: String, name: String, glyph: String
        var twin: String
        let words: String
        let pipes: [String: Data]      // a correspondence's reference -> its secret: their book and the pipes met on the shelf
        let invites: [String: Data]    // an invitation of their cards -> the card's body (the first 1184 bytes are its root)
        let cardKeys: [String: Data]   // a card's root -> its secret key
        let outbox: [MTOutbox.Item]    // their own queue, parked with them
        let firsts: Set<String>         // their pipes nobody has answered yet: a letter on one goes as a first letter, from their own engine
    }
    private static let lock = NSLock()
    private static var running = false
    private static var lastAt: Double = 0
    private static var twins: [String: String] = [:]   // a person's reference derived once per process when their store keeps none

    /// A pickup of the person seated asks for one: one walk at a time, and not twice in twenty seconds.
    static func soon() {
        let go: Bool = lock.withLock {
            let now = Date().timeIntervalSince1970
            guard !running, now - lastAt >= 20 else { return false }
            running = true; lastAt = now
            return true
        }
        guard go else { return }
        Task.detached(priority: .utility) {
            for p in MTSeats.shelfPeople() { await serve(p) }
            lock.withLock { running = false }
        }
    }

    /// The reference this person signs their subscriptions with: kept by their store, or derived from their words once.
    private static func twin(_ p: Person) -> String {
        if !p.twin.isEmpty { return p.twin }
        if let t = lock.withLock({ twins[p.id] }) { return t }
        guard let master = MontanaQueueKeys.masterSeed(p.words), let owner = MTPipe.ownerSecret(masterSeed: master),
              let ref = MTPipeBook.reference(of: owner) else { return "" }
        lock.withLock { twins[p.id] = ref }
        return ref
    }

    private static func serve(_ person: Person) async {
        var p = person
        p.twin = twin(p)
        guard !p.twin.isEmpty, !MontanaWakePush.doorsHolding("box").isEmpty else { return }
        let ear = MontanaWakePush.BoxEar(invites: p.invites.keys.compactMap { Data(base64urlNoPad: $0) }.filter { $0.count == 32 },
                                         pipes: p.pipes, owner: p.twin)
        guard !ear.subs.isEmpty else { return }
        var held: [[String: String]] = []
        let kept = await MontanaWakePush.pickup(ear, buries: nil, keep: { row in
            guard MTSeats.fileShelf(p.id, rows: [row]) else { return false }
            held.append(row)
            return true
        })
        MontanaP2PTrace.mark("shelf_post", "seat=\(p.id) subs=\(ear.subs.count) kept=\(kept)")
        for row in held { await answer(row, for: p) }
        await carry(p)
    }

    private static var carried: [String: Double] = [:]   // a letter of a person on the shelf -> the moment it last rode from here
    /// THEIR OWN LETTERS RIDE: a letter the person wrote before they left the seat waits in their own queue on the shelf; it rides
    /// from here under their own reference on the rhythm of a letter that waits for its receipt (five minutes), and its receipt
    /// comes back to their inbox on the shelf, where the landing settles their queue at the lift. A media letter, a letter on a
    /// pipe nobody has answered yet and a letter too long for one envelope wait for the person's own engine.
    private static func carry(_ p: Person) async {
        let doors = MontanaWakePush.oneDoorPerNode(MontanaWakePush.orderedBases(for: "box"))
        let now = Date().timeIntervalSince1970
        for it in p.outbox where it.kind == .letter && !it.text.hasPrefix(mediaMark) && !p.firsts.contains(it.to) {
            guard let secret = p.pipes[it.to], lock.withLock({ now - (carried[it.mid] ?? 0) >= 300 }),
                  let plain = MTNodeWire.padEnvelope(MTNodeWire.letterHead(mid: it.mid, text: it.wire ?? it.text, name: p.name, glyph: p.glyph,
                                                                         quoteText: it.qt, quoteMid: it.qm)) else { continue }
            lock.withLock { carried[it.mid] = now }
            let k = await MTNodeWire.knockLetter(secret: secret, twinRef: p.twin, mid: it.mid, plain: plain, doors: doors, silent: it.silent)
            MontanaP2PTrace.mark("shelf_carry", mid: it.mid, "seat=\(p.id) boxed=\(k.boxed ? 1 : 0) code=\(k.code) silent=\(it.silent ? 1 : 0)")
        }
    }

    /// A row in the person's hands: a first letter meets its pipe; words and coins are receipted; coins reach their book.
    private static func answer(_ row: [String: String], for p: Person) async {
        guard let mid = row["m"], let text = row["t"], !mid.isEmpty else { return }
        var conv = row["c"] ?? ""
        var secret = p.pipes[conv]
        if conv == "rdv" {
            guard let met = meet(row, for: p) else { return }
            conv = met.ref; secret = met.secret
        }
        guard let secret, !conv.isEmpty else { return }
        // Only what a person reads is receipted here: words and coin letters. Media waits for its cargo at the lift, and a
        // service word (a mark, a name, a face, a read) asks no receipt of a person who is not on the screen.
        let words = !text.hasPrefix("\u{200B}") && !text.hasPrefix("\u{2063}")
        guard words else { return }
        let rmid = ChatStore.receiptMid(mid)
        if let plain = MTNodeWire.padEnvelope(MTNodeWire.letterHead(mid: rmid, text: deliveryReceiptMark + mid, name: p.name, glyph: p.glyph)) {
            let k = await MTNodeWire.knockLetter(secret: secret, twinRef: p.twin, mid: rmid, plain: plain,
                                                 doors: MontanaWakePush.oneDoorPerNode(MontanaWakePush.orderedBases(for: "box")), silent: true)
            MontanaP2PTrace.mark("shelf_receipt", mid: mid, "seat=\(p.id) boxed=\(k.boxed ? 1 : 0) code=\(k.code)")
        }
        if let coin = MTCoinLetter.parse(text), coin.bound(to: mid),
           let e = MontanaSeedKeys.entropyFrom(mnemonic: p.words), e.count == 32 {
            let move = MTCoinEntry(k: .receive, c: coin.c, ref: "mid:" + mid, peer: conv, on: nil, at: Date().timeIntervalSince1970)
            let laid = await MTCoinVault.lay([move], entropy: e)
            MontanaP2PTrace.mark("shelf_coin", mid: mid, "seat=\(p.id) coins=\(coin.c) rows=\(laid)")
        }
    }

    /// THE SHELF RINGS THE PHONE (07.10): the labels of every person on the shelf, signed by their own reference, join the wake
    /// registration of this phone's token after the person seated (the node trims the tail first); the keys their letters open
    /// with go to the notification extension (MTNodeWire.ShelfEar), which shows whose a letter is.
    /// A PIPE BETWEEN TWO PERSONS OF THIS PHONE RINGS NOBODY (07.10, the author's word «on T1 the second account duplicates the
    /// posts»): the seated person holds the same secret, so a ring for the shelf on it was a ring for the seated person's own letter
    /// -- the extension opened it with the seated person's key and laid it as the other's (17:00:24Z: T1's own wall page came back
    /// as the second account's, every post twice in the feed). The phone holds both ends of such a pipe: the shelf's pickup and
    /// the lift carry it, no ring. seatedHolds answers from the seated person's own book, asked by its owner (registerRound).
    static func wakePairs(_ w0: UInt64, seatedHolds: (Data) -> Bool) -> [[String: String]] {
        var pairs: [[String: String]] = []
        var ears: [MTNodeWire.ShelfEar] = []
        for person in MTSeats.shelfPeople() {
            var p = person
            p.twin = twin(p)
            guard !p.twin.isEmpty else { continue }
            let own = p.pipes.filter { !seatedHolds($0.value) }
            var keys = own
            var labels: [String] = []
            for inv in p.invites.keys.compactMap({ Data(base64urlNoPad: $0) }).filter({ $0.count == 32 }) {
                keys["rdv:" + inv.base64urlNoPad] = MontanaWakePush.rdvLetterSecret(inv)
                for w in (w0 - 1)...(w0 + 2) { labels.append(MontanaWakePush.rdvConvW(inv, window: w)) }
            }
            for secret in own.values {
                for w in (w0 - 1)...(w0 + 2) { labels.append(MontanaWakePush.convW(secret, window: w)) }
            }
            pairs += labels.map { cw in ["conv": cw, "sid": MontanaWakePush.subId(cw, ref: p.twin)] }
            ears.append(MTNodeWire.ShelfEar(seat: p.id, name: p.name, keys: keys))
        }
        MTNodeWire.writeShelfEars(ears)
        return pairs
    }

    /// A first letter to the person's card, opened with the card's own key and proven by its confirmation -- the pipe is kept
    /// on the shelf until the lift, where the landing door gives it birth in the person's own book.
    private static func meet(_ row: [String: String], for p: Person) -> (ref: String, secret: Data)? {
        guard let inv = row["i"], let k = row["k"], let ct = Data(base64Encoded: k), ct.count == 1088,
              let body = p.invites[inv], body.count >= 1184 else { return nil }
        let root = body.prefix(1184)
        guard let sk = p.cardKeys[root.base64urlNoPad],
              let secret = MontanaFirstContact.accept(ciphertext: ct, contactSecret: sk, contactRoot: Data(root)),
              MontanaFirstContact.sameConfirm(row["cf"] ?? "", MontanaFirstContact.firstConfirm(secret: secret, ct: ct)),
              let ref = MTPipeBook.reference(of: secret) else {
            MontanaP2PTrace.mark("shelf_meet", "seat=\(p.id) refused")
            return nil
        }
        guard MTSeats.meetOnShelf(p.id, ref: ref, secret: secret) else { return nil }
        MontanaP2PTrace.mark("shelf_meet", "seat=\(p.id) ref=\(String(ref.prefix(10)))")
        return (ref, secret)
    }
}
