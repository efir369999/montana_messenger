import Foundation
import SwiftUI

/// MESSENGER'S EDITION (docs/APPS-API.md, rule 3 and slices S5 and S8): Messenger carries no coins, no VPN, no chess, no wall, no
/// YouTube and no Passwords -- their files are not in this target, so every door is nil and shared code draws none of them
/// (rule 4). The target's list of files is the only switch between editions.
enum MTEdition {
    static let coins: MTCoinDoor? = nil
    static let vpn: MTVPNDoor? = nil
    static let chess: MTChessDoor? = nil
    static let wall: MTWallDoor? = nil
    static let messenger: MTMessengerDoor? = nil   // no Organizations: no roster, shifts, supply or work chats (the author's word 04.11.2026 11:32 UTC, link 16078)
    /// NO YOUTUBE PLAYS IN MESSENGER (App Review 5.2.2, critic of S5r, link 15358): a YouTube link opens where it lives. No call is
    /// recorded in either edition (the author's word 16428, 04.11.2026).
    static let youtube: MTYouTubeDoor? = nil
    static let mesh: MTMeshDoor? = nil   // no radio, no mesh wall (links 15844-15846)
    static let passwords: MTPasswordsDoor? = nil   // no Passwords: no tile, no page, no vault (link 15962)
    /// NO OWN NODE IN MESSENGER (decision 531 (a)): Settings draw no row of it, and it never acts -- a function the person cannot
    /// see never acts for them.
    static let ownNode = false
    /// NO LEVELS IN MESSENGER (decision 618 (b), the author's word 16339): no badge at the avatar, no line of levels in Settings,
    /// no level said to a pair or in a call's caps, none published to the nodes' table -- the Protocol keeps them all.
    static let levels = false
    /// MONTANA MESSENGER'S SITE (App Review 5.1.1(i)): its page and its own privacy policy, montana.xxx/privacy/.
    static let site = "https://montana.xxx"
    /// MONTANA MESSENGER'S FACE (App Review 2.3.7, one face everywhere; decision 549, no coins): its own icon, never Montana
    /// Protocol's coin -- the shared catalog serves both targets, so the Messenger's pictures stand in its own catalog
    /// (Code/Messenger/MessengerAssets.xcassets, rendered by ictool from Code/Messenger/AppIcon.icon).
    static let face = "MessengerGlassPreview"
    static let cover = "MessengerIconPicture"
    /// THE FIRST SCREEN'S LINE (the author's words 16364 and 16543, 04.11.2026: Montana is the anonymous messenger).
    static let intro: LocalizedStringResource = "An anonymous messenger. Your identity comes from your secret phrase, and your chats are encrypted on your device."
}
