import SwiftUI

// ════════════════════════════════════════════════════════════
// PEER INFO — the vocabulary of the profile: what a row can be, which section it belongs to, and the
// one renderer that draws any list of them. The screen composes rows; it never draws a card by hand.
// ════════════════════════════════════════════════════════════

// SSOT of the separator inside a card: one line, one colour, the inset given by the row it follows.
// Two hand-written dividers with different insets is how one card came to look different on two
// screens, so every card on every screen takes its separator from here.
func mtCardDivider(inset: CGFloat) -> some View {
    Divider().overlay(Color.gray.opacity(0.15)).padding(.leading, inset)
}

// The sections of the profile, in the order they appear. A section that collects no rows is not
// drawn, so the order is declared once here and the screen never decides placement by nesting.
enum MTInfoSection: Int, CaseIterable, Identifiable {
    case about     // a group's description, above its people (the reference folder's group page, stage R)
    case members
    case peerInfo
    case chatSettings

    var id: Int { rawValue }
}

// One row of the profile. The case decides how it is drawn and how far its separator is inset; the
// screen supplies only the words and the action.
struct MTInfoRow: Identifiable {
    enum Kind {
        case header(LocalizedStringKey)
        case labeledValue(value: String, caption: LocalizedStringKey)
        case disclosure(title: LocalizedStringKey, detail: LocalizedStringKey, icon: String, tint: Color, action: () -> Void)
        case action(title: LocalizedStringKey, icon: String, destructive: Bool, action: () -> Void)
        case toggle(title: LocalizedStringKey, icon: String, isOn: Binding<Bool>)
        case member(name: String, subtitle: LocalizedStringKey, removable: Bool, onRemove: () -> Void, deeds: [MTMemberDeed] = [])
    }

    let id: String
    let kind: Kind

    var dividerInset: CGFloat {
        switch kind {
        case .header, .labeledValue: return 14
        case .disclosure, .action, .toggle: return 50
        case .member: return 64
        }
    }
}

// One card, any rows. Separators come between adjacent rows only, so a card of one row has none and a
// card of five has four — the rule lives here instead of at every call site.
// Every section that has rows, in declared order.
/// THE PROFILE'S ROWS ARE THE PLATFORM'S GROUPED LIST (the author's word 18.09: native, in the
/// app's grey, as every settings page): every section is a List section — its header row the
/// section's own header, its rows the list's rows with the list's own separators and insets.
/// THE ROWS STAND ON THE SYSTEM'S GLASS (the author's word 25.09: the rows between the buttons and the tabs
/// transparent, in the dress of the buttons and the tab strip): the one glass plate of the tree (MTGlassRowPlate) --
/// the wall's rows and the settings' cards wear it -- so the page's ground shows through them as it does through the
/// buttons' plates and the strip; a dead grey stood there and looked another page.
struct MTInfoSectionsView: View {
    let sections: [MTInfoSection: [MTInfoRow]]

    var body: some View {
        ForEach(MTInfoSection.allCases) { section in
            if let rows = sections[section], !rows.isEmpty {
                let cut = Self.split(rows)
                Section {
                    ForEach(cut.rows) { row in MTInfoRowView(row: row).listRowInsets(EdgeInsets()) }
                } header: {
                    if let h = cut.header { Text(h) }
                }
                .listRowBackground(MTGlassRowPlate())   // the system's one-tone glass, as the wall's rows (the author's word 25.09)
            }
        }
    }
    static func split(_ rows: [MTInfoRow]) -> (header: LocalizedStringKey?, rows: [MTInfoRow]) {
        if let first = rows.first, case .header(let h) = first.kind { return (h, Array(rows.dropFirst())) }
        return (nil, rows)
    }
}

struct MTInfoRowView: View {
    let row: MTInfoRow

    var body: some View {
        switch row.kind {
        case .header(let title):
            Text(title)
                .font(.caption).foregroundColor(.gray)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 4)

        case .labeledValue(let value, let caption):
            VStack(alignment: .leading, spacing: 2) {
                Text(value).foregroundColor(.white).textSelection(.enabled)
                Text(caption).font(.caption).foregroundColor(.gray)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14).padding(.vertical, 10)
            .contentShape(Rectangle())
            .onTapGesture { UIPasteboard.general.string = value }
            .contextMenu {
                Button { UIPasteboard.general.string = value } label: { Label("Copy", systemImage: "doc.on.doc") }
            }

        case .disclosure(let title, let detail, let icon, let tint, let action):
            Button(action: action) {
                HStack(spacing: 12) {
                    Image(systemName: icon).foregroundColor(tint).frame(width: 24)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(title).foregroundColor(.white)
                        Text(detail).font(.caption2).foregroundColor(tint)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption).foregroundColor(.gray)
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
                .contentShape(Rectangle())   // the whole row answers, not the word alone (the author's word 22.09)
            }

        case .action(let title, let icon, let destructive, let action):
            Button(action: action) {
                HStack(spacing: 12) {
                    Image(systemName: icon)
                        .foregroundColor(destructive ? .red : .gray).frame(width: 24)   // grey glyphs, red only for report and block (18.09)
                    Text(title).foregroundColor(destructive ? .red : .white)   // the list's own word colour (18.09)
                    Spacer()
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
                .contentShape(Rectangle())   // the whole row answers, not the word alone (the author's word 22.09)
            }

        case .toggle(let title, let icon, let isOn):
            Toggle(isOn: isOn) {
                Label {
                    Text(title).foregroundColor(.white)
                } icon: {
                    Image(systemName: icon).foregroundColor(.white)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 8)

        case .member(let name, let subtitle, let removable, let onRemove, let deeds):
            HStack(spacing: 12) {
                AvatarCircle(photoURL: nil,
                             color: Color(montanaHexString: MontanaAvatar.colorHex(name)),
                             initial: MontanaAvatar.initial(title: name, name: ""), size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).foregroundColor(.white)
                    Text(subtitle).font(.caption).foregroundColor(.gray)
                }
                Spacer()
                if removable {
                    Button(action: onRemove) {
                        Image(systemName: "minus.circle.fill").foregroundColor(.red)
                            .frame(width: 44, height: 44).contentShape(Rectangle())   // the platform's minimum target (18.09)
                    }
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .contentShape(Rectangle())
            // THE PERSON'S DEEDS ON A HOLD (stage R.6, the reference folder's member menu): promote, dismiss, remove
            .contextMenu {
                ForEach(deeds) { d in
                    Button(role: d.destructive ? .destructive : nil, action: d.action) { Label(d.title, systemImage: d.icon) }
                }
            }

        }
    }
}

/// One deed over a person of a group on its page (stage R.6, the reference folder's member menu): promote, dismiss, remove.
struct MTMemberDeed: Identifiable {
    let id: String
    let title: LocalizedStringKey
    let icon: String
    var destructive = false
    let action: () -> Void
}
