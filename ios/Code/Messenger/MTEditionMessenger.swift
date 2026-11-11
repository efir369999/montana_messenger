import Foundation
import SwiftUI

/// MESSENGER'S EDITION (docs/APPS-API.md, rule 3 and slices S5 and S8): Messenger carries no coins -- their files are not in this
/// target, so the door is nil and shared code draws none of them (rule 4). The target's list of files is the switch between
/// editions; a door of an application the Messenger lacks is not even declared here (MTApps.swift, MONTANA_MESSENGER; cuts C4-C6).
enum MTEdition {
    // NO YOUTUBE PLAYS IN MESSENGER (App Review 5.2.2, critic of S5r, link 15358): a YouTube link opens where it lives -- its door
    // and uses stand under #if !MONTANA_MESSENGER (cut C4). No call is recorded in either edition (the author's word 16428,
    // 04.11.2026).
    /// NO OWN NODE IN MESSENGER (decision 531 (a)): Settings draw no row of it, and it never acts -- a function the person cannot
    /// see never acts for them.
    static let ownNode = false
    // NO LEVELS IN MESSENGER (decision 618 (b), the author's word 16339): their code stands under #if !MONTANA_MESSENGER (cut C3a)
    // -- no badge at the avatar, no line of levels in Settings, no level said to a pair, none published to the nodes' table.
    /// MONTANA MESSENGER'S SITE (App Review 5.1.1(i); the author's words 18128, 18136 and 18155, 10.11.2026: montana.one is the
    /// Messenger's own site, on Amsterdam): its page, its own privacy policy montana.one/privacy/ and its release feed /updates/.
    static let site = "https://montana.one"
    /// THE MESSENGER'S CARDS are on its own site: montana.one serves /r/ /perp/ /temp/ and the association file naming this bundle.
    static let cards = site
    /// MONTANA MESSENGER'S FACE (App Review 2.3.7, one face everywhere; decision 549, no coins): its own icon, never Montana
    /// Protocol's coin -- the shared catalog serves both targets, so the Messenger's pictures stand in its own catalog
    /// (Code/Messenger/MessengerAssets.xcassets, rendered by ictool from Code/Messenger/AppIcon.icon).
    static let face = "MessengerGlassPreview"
    static let cover = "MessengerIconPicture"
    /// WHAT TURNS UNDER A PULL (MontanaPullSpinner; the author's word 18349, 10.11.2026: Messenger's code carries none of the
    /// Protocol's): Messenger's own face on both sides -- its back, mirrored back by the turn, reads the same.
    static let pullFace = cover
    static let pullBack = cover
    /// THE FIRST SCREEN'S LINE (the author's words 16364 and 16543, 04.11.2026: Montana is the anonymous messenger).
    static let intro: LocalizedStringResource = "An anonymous messenger. Your identity comes from your secret phrase, and your chats are encrypted on your device."
    /// DELETE ERASES (App Review 5.1.1(v); the author's decision (a), 10.11.2026): «Delete account» says what leaves -- the identity,
    /// the history and its attachments, the keepers' parts, the copies in iCloud -- and what a keeper who is away still holds.
    static let deletion: LocalizedStringResource = "Your account is deleted from this device: your 24-word identity, your history and its attachments are erased here, the people who keep parts of your copy are asked to drop them, and your copies in iCloud are removed. A contact who is offline keeps a sealed part that nothing but your 24 words can open. Your other devices keep what they hold. This cannot be undone."
    static let deleting: LocalizedStringResource = "Deleting…"
}
