import SwiftUI

// THE SHARED PLATES (docs/APPS-API.md, section 4 and slice S4a): the glass every settings page, the chats, the calls and Messenger's
// own pages stand on. They lived beside the wall's views (MontanaBoardViews) and belong to no application: every edition carries
// them, and the wall's door is cut over them.

/// THE GLASS OF A PLATE IS RENDERED IN ITS OWN CONTAINER (26.09, the author's word: «check and close at the root every doubt, so
/// that the glass works one hundred percent right»). The platform's own words (SwiftUI, «Applying Liquid Glass to custom views»):
/// «The glassEffect(_:in:) modifier captures the content to send to the container to render. Apply the glassEffect(_:in:)
/// modifier after other modifiers that affect the appearance of the view.» A plate's glass had no container of its own: the
/// implicit one stood far above it, and between the two stood our changes of look made after the glass -- the clip of the
/// bubble's shape (thirteen of them), the feed's flip, the cell. In its own GlassEffectContainer the glass is rendered where it
/// stands, and whatever the plate's hosts do after is done to a finished plate. One owner of the plate's glass: every plate of
/// the tree -- a letter's, a post's, a row's, a card's, a circle's, a sheet's -- stands on it.
@available(iOS 26.0, *)
struct MTGlassPlate<S: Shape>: View {
    var glass: Glass = .regular
    let shape: S
    var body: some View {
        GlassEffectContainer { Color.clear.glassEffect(glass, in: shape) }
    }
}

/// A ROW'S GLASS PLATE (the author's word 25.09: «transparent liquid glass, a transparent glass plate, not a dead grey»): the
/// system's glass where it has it, the thin material before — the plate the field and the bar wear.
struct MTGlassRowPlate: View {
    var body: some View {
        if #available(iOS 26.0, *), MontanaSkin.isNative {
            MTGlassPlate(shape: Rectangle())
        } else {
            Rectangle().fill(MontanaOctagon.barMaterial)
        }
    }
}

/// A CARD'S GLASS PLATE (the author's word 25.09: «the settings' panel of buttons transparent, in the native liquid glass, as
/// everything else»): the system's glass in the card's own rounded shape where it has it, the thin material before.
struct MTGlassCardPlate: View {
    var cornerRadius: CGFloat = 12
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(iOS 26.0, *), MontanaSkin.isNative {
            MTGlassPlate(shape: shape)
        } else {
            shape.fill(MontanaOctagon.barMaterial)
        }
    }
}

struct MTGlassCirclePlate: View {
    var body: some View {
        if #available(iOS 26.0, *), MontanaSkin.isNative {
            MTGlassPlate(shape: Circle())
        } else {
            Circle().fill(MontanaOctagon.barMaterial)
        }
    }
}

/// A SHEET OF GLASS (25.09): the page behind shows through the system's own glass where it has it, the thin material before —
/// the ground of the new post's page, a tree of its own on the platform's sheet (its host's own view is clear).
struct MTGlassSheet: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 26.0, *), MontanaSkin.isNative {
            content.background { MTGlassPlate(shape: Rectangle()).ignoresSafeArea() }
        } else {
            content.background { Rectangle().fill(.ultraThinMaterial).ignoresSafeArea() }
        }
    }
}
