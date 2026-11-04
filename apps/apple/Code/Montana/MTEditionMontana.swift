import Foundation

/// MONTANA'S EDITION (docs/APPS-API.md, rule 3): the doors this target fills. Each edition is a target with its own file holding
/// this one type, named after the edition, since a file's name is one under Code (mt-typecheck); the target's list of files is the
/// only switch between editions.
enum MTEdition {
    static let coins: MTCoinDoor? = MTCoinsDoor()
    static let vpn: MTVPNDoor? = MTVPNAppDoor()
    static let chess: MTChessDoor? = MTChessAppDoor()
    static let wall: MTWallDoor? = MTWallAppDoor()
    static let messenger: MTMessengerDoor? = nil
    static let youtube: MTYouTubeDoor? = MTYouTubeAppDoor()
    static let mesh: MTMeshDoor? = MTMeshAppDoor()
    static let passwords: MTPasswordsDoor? = MTPasswordsAppDoor()
    /// NO ROW OF ONE'S OWN NODE (the author's word 16428, 04.11.2026: «the item YOUR NODE -- delete it too»): Settings draw none and the
    /// node sends nothing -- a function the person cannot see never acts for them; a file it already holds still comes back.
    static let ownNode = false
    /// THE LEVELS AS REPUTATION (MTLevels, MTAvatarBadgePair): the Protocol carries them; Messenger carries none (decision 618 (b)).
    static let levels = true
    /// The Protocol's site: its page and its privacy policy, montana.quest/privacy/.
    static let site = "https://montana.quest"
    /// MONTANA PROTOCOL'S FACE (the author's word 15590, 03.11.2026: his coin is this app's icon): the glass icon on the first
    /// screen, the room's face and the icon chooser's first place, and the flat picture a track without a cover wears.
    static let face = "IconGlassPreview"
    static let cover = "AppIconPicture"
    /// THE FIRST SCREEN'S LINE (the author's words 16364 and 16543, 04.11.2026: MT Protocol is next-generation communication,
    /// Montana the anonymous messenger): each edition says what it is, the shared screen reads it.
    static let intro: LocalizedStringResource = "Next-generation communication. Your identity comes from your secret phrase, and everything you send is encrypted on your device."
}
