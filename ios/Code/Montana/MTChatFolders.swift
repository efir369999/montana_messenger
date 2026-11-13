import SwiftUI
import UIKit

/// THE FOLDERS OVER THE CHATS (the author's words 17.10.2026 15:4x UTC: «badges over the chats, the groups and the channels, and
/// their control in the settings»; «left of the chats, the groups and the channels a field All, every chat in it, the groups and
/// the channels too -- and a category Bots, our bot in it» -- the bot and its category taken out whole by the author's word 16283,
/// 04.11.2026; «the groups and the channels one to one»). The
/// folders: All Chats and the person's folders, each the kinds of chats and the chats it takes and the states and the
/// chats it leaves out; a tab's badge counts the folder's unread conversations and is blue while one of them is not muted. A setting
/// of the person: kept in the vault and carried by the copy (SeedScope.settingKeys). NO FOLDERS' PAGE AND NO TABS (the author's
/// words 19110 and 19116 and decision 831 = a, 11.11.2026): the chats page shows every chat, the drawer's Groups and Channels open
/// the folder of their kind, and the folders are only read.
struct MTChatFolder: Codable, Identifiable, Hashable {
    enum Kind: String, Codable, CaseIterable {
        case contacts, nonContacts, groups, channels
    }
    enum Leave: String, Codable, CaseIterable {
        case muted, read, archived
    }
    var id: String
    /// The person's own words; empty while a first-launch folder keeps the name of its kind in the person's language.
    var title: String = ""
    var preset: Kind? = nil
    var kinds: [Kind] = []
    var chats: [String] = []
    var leaves: [Leave] = [.archived]
    var excluded: [String] = []

    static let allID = "all"
    static let all = MTChatFolder(id: allID, leaves: [])
    var isAll: Bool { id == Self.allID }
    /// The folder of one kind alone: the drawer's Groups and Channels open theirs, and its corner gives birth to that kind.
    var onlyKind: Kind? { kinds.count == 1 && chats.isEmpty ? kinds.first : nil }
    var takesAnything: Bool { !kinds.isEmpty || !chats.isEmpty }
    /// Whether a conversation stands in the folder: taken by its kind or by name, not left out by name or by a state.
    func takes(_ c: Chat, kind: Kind, muted: Bool, unread: Bool, archived: Bool) -> Bool {
        if isAll { return !archived }
        if excluded.contains(c.name) { return false }
        guard kinds.contains(kind) || chats.contains(c.name) else { return false }
        if muted && leaves.contains(.muted) { return false }
        if !unread && leaves.contains(.read) { return false }
        if archived && leaves.contains(.archived) { return false }
        return true
    }
}

extension MTChatFolder {
    /// A KIND THIS BUILD NO LONGER KNOWS IS DROPPED, NOT THE FOLDERS (the author's word 16283, 04.11.2026: our bot and its category are
    /// taken out whole): a folder kept naming «bots» reads on without it, so the person's folders never fall back to the first ones.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        preset = try c.decodeIfPresent(String.self, forKey: .preset).flatMap(Kind.init(rawValue:))
        kinds = try c.decode([String].self, forKey: .kinds).compactMap(Kind.init(rawValue:))
        chats = try c.decode([String].self, forKey: .chats)
        leaves = try c.decode([Leave].self, forKey: .leaves)
        excluded = try c.decode([String].self, forKey: .excluded)
    }
}

/// The person's folders in the tabs' order, All Chats among them and never taken away.
final class MTChatFolders: ObservableObject {
    static let shared = MTChatFolders()
    static let key = "chatFolders"
    @Published private(set) var folders: [MTChatFolder]
    private init() {
        let raw = MontanaLocalVault.getString(Self.key) ?? ""
        // A folder left taking nothing -- the bots' tab of a build before the author's word 16283 -- leaves on load.
        let kept = ((try? JSONDecoder().decode([MTChatFolder].self, from: Data(raw.utf8))) ?? []).filter { f in f.isAll || f.takesAnything }
        folders = kept.contains(where: { f in f.isAll }) ? kept : Self.firstFolders
    }
    /// THE FIRST TABS, in the author's order (17.10.2026): All, the chats, the groups, the channels -- the bots' tab went with the bot
    /// (the author's word 16283, 04.11.2026).
    static let firstFolders: [MTChatFolder] = [
        .all,
        MTChatFolder(id: "chats", preset: .contacts, kinds: [.contacts, .nonContacts]),
        MTChatFolder(id: "groups", preset: .groups, kinds: [.groups]),
        MTChatFolder(id: "channels", preset: .channels, kinds: [.channels])]

    func folder(_ id: String) -> MTChatFolder? { folders.first { f in f.id == id } }
    func folder(only kind: MTChatFolder.Kind) -> MTChatFolder? { folders.first { f in f.onlyKind == kind } }
    /// The address book is read only while a folder tells the contacts from the rest: the first folders take both.
    var tellsContacts: Bool { folders.contains { f in f.kinds.contains(.contacts) != f.kinds.contains(.nonContacts) } }
    static func contactRefs() -> Set<String> {
        let raw = MontanaLocalVault.getString("mtContacts") ?? ""
        let book = (try? JSONDecoder().decode([ContactsTabView.MTContact].self, from: Data(raw.utf8))) ?? []
        return Set(book.map { c in c.ref })
    }
    /// What a conversation is to the folders -- one answer for the tabs, their badges and the folders' page.
    static func kind(of c: Chat, contacts: Set<String>?) -> MTChatFolder.Kind {
        if MTGroup.isKey(c.name) { return MTGroup.shared.kind(c.name) == .channel ? .channels : .groups }
        return contacts?.contains(c.convRef) == true ? .contacts : .nonContacts
    }
    /// A folder's rows in the chats' one order: the rows of the list, and the archived ones where the folder keeps them.
    func rows(of f: MTChatFolder, live: [Chat], archived: [Chat], store: ChatStore, contacts: Set<String>?) -> [Chat] {
        if f.isAll { return live }
        let keep: (Chat, Bool) -> Bool = { c, gone in
            f.takes(c, kind: Self.kind(of: c, contacts: contacts), muted: store.mutedChats.contains(c.name),
                    unread: store.hasUnread(c.name), archived: gone)
        }
        let here = live.filter { c in keep(c, false) }
        return f.leaves.contains(.archived) ? here : here + archived.filter { c in keep(c, true) }
    }
}
