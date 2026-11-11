import SwiftUI
import UIKit
import Security
import UniformTypeIdentifiers
import MontanaBindings

#if !MONTANA_MESSENGER   // the Wi-Fi neighbours are the mesh's scan: no picker of them in Messenger (15846)
/// P2P network test (serverless self-host). The node comes up ITSELF when the app opens —
/// the screen only reflects status and shows the card automatically. There is no manual "connect".
/// Sending: paste the peer's card (still manual for now; mDNS auto-discovery is the next step).
// Nearby-devices picker (green Wi-Fi indicator). Tapping a device opens the SAME chat
// as scanning their QR / adding by address — messages then travel over the Wi-Fi mesh (no server).
struct MontanaP2PPeersSheet: View {
    @EnvironmentObject private var store: ChatStore
    let onOpenChat: (String) -> Void            // (montana address) -> open the normal chat
    @ObservedObject private var node = MontanaPhoneNode.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List {
                if node.peers.isEmpty {
                    Text("No devices nearby. Open Montana on another phone on the same Wi-Fi.")
                        .font(.callout).foregroundColor(.secondary)
                } else {
                    ForEach(node.peers) { peer in
                        Button {
                            guard !peer.neighborRef.isEmpty else { return }
                            dismiss(); onOpenChat(peer.neighborRef)
                        } label: {
                            HStack(spacing: 12) {
                                Circle().fill(Color.green.opacity(0.16)).frame(width: 42, height: 42)
                                    .overlay(Image(systemName: "person.fill").foregroundColor(.green))
                                VStack(alignment: .leading, spacing: 3) {
                                    // The name this person chose for themselves, from the same resolver the
                                    // chats and the call screen use ([I-10]); the address below it is the
                                    // part nobody can choose.
                                    // USER-DATA: a neighbour name, not interface text.
                                    Text(verbatim: MontanaName.of(peer: peer))
                                        .font(.system(size: 14, weight: .semibold)).foregroundColor(.primary)
                                    Text("Wi-Fi")
                                        .font(.system(size: 10, design: .monospaced)).foregroundColor(.secondary)
                                }
                                Spacer()
                                Image(systemName: "message.fill").foregroundColor(.green)
                            }
                            .contentShape(Rectangle())   // the whole row is the target, not only its words (22.09)
                        }
                        .disabled(peer.neighborRef.isEmpty)
                    }
                }
            }
            .navigationTitle("Devices nearby")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { MontanaDoneMark { dismiss() } } }
        }
    }

    static func shortEndpoint(_ a: String) -> String {
        a.count > 22 ? String(a.prefix(12)) + "…" + String(a.suffix(8)) : a
    }
}
#endif


// THE NETWORK UNDER THE TIME PANEL (the author's word 25.09: «make the network page a full page under the time panel, with
// no border above or below, as the chats, the calls, the contacts and the feed are»): a page of the finger's row
// (UIState.Pane.network), chosen as every page is -- by the globe on the bar, by the drawer's row, by a stroke -- with the puck
// under the globe. It stands on the one container of the pages under the bar (MontanaTimePanelList): the panel's head at its
// head, its rows running on to the screen's edges under the panel and the home strip, the page's own crest ground. Everything
// the page shows is a row of that list -- the head (the three tabs, the power, the timer), each plan's header, each server, the
// hand-added servers' header, the nodes -- printed by what it draws, so a ping, a fold, a pin or the
// tunnel's word moves its own row alone (the calls' law, rowPrint). The tap, the hold and the swipe are the container's own
// (15.26, 16.09): a tap on a server chooses it, a hold opens its menu, the swipe from the left measures it and the swipe from the
// right pins or deletes it. The plus stands bottom right as the music's plus and the chats' write do; the page searches itself
// as the music and the feed do. The page over the tabs it was (NavigationView, a toolbar, a close, a List) is gone with the
// page's rebirth at every touch of the globe -- the class of 1938, closed for the pages under the bar on 25.09.
/// THE P2P NETWORK (the author's word 29.09: the network is disbanded into three applications): the nodes this phone reaches.
/// The VPN is its own page since slice S3a (MontanaVPNPage, MTApps.vpn); the mesh is its own page since link 15898
/// (MTApps.mesh), so no word of the mesh is drawn here.
struct NetworkTabView: View {
    @EnvironmentObject private var store: ChatStore
    @Environment(UIState.self) private var ui
    let panel: MontanaTimePanel
    @ObservedObject private var node = MontanaPhoneNode.shared

    // THE ROWS OF THE PAGE, each named by what it is: the head, the nodes. The name is the row's identity for the list's
    // differences (Chat.id).
    private static let headMark = "net:head"
    private static let p2pMark = "net:p2p"
    private static func chatRow(_ id: String) -> Chat { Chat(name: id, lastMessage: "", time: "", unread: 0, status: "", convId: id) }
    private var rows: [Chat] { [Self.chatRow(Self.headMark), Self.chatRow(Self.p2pMark)] }

    /// The print's fields by name, in its order -- the diary names a changed row's field by them; the VPN page's and the mesh
    /// page's prints have the same shape. A field a kind does not draw stays zero.
    static let printNames = ["id", "tab", tunnelField, "line", "count", "fold", "pin", "moment", "word", "selected", "ping"]
    /// The third place is the VPN page's tunnel; this page never draws it, and Montana Messenger compiles no word of a tunnel
    /// (decision 651 = a) -- there the place keeps the shape under no name.
    #if MONTANA_MESSENGER
    private static let tunnelField = "-"
    #else
    private static let tunnelField = "tunnel"
    #endif
    private func rowPrint(_ c: Chat) -> [Int] {
        func p<T: Hashable>(_ v: T) -> Int { var h = Hasher(); h.combine(v); return h.finalize() }
        var out = [p(c.id)] + Array(repeating: 0, count: Self.printNames.count - 1)
        if c.id == Self.headMark {
            out[4] = p(MontanaNodes.liveNodes)
            out[8] = p(node.nodeUp)
        } else if c.id == Self.p2pMark {
            out[4] = p([MontanaNodes.liveNodes, MontanaNodes.list().count])
            out[8] = p(MontanaNodes.live().map { $0.label } + MontanaNodes.list().map { $0.label })
        }
        return out
    }

    var body: some View {
        let _ = MTFrameMeter.shared.body("network")   // the page's passes while a motion is measured
        // THE ROWS RUN ON TO THE SCREEN'S EDGES, AS THE CHATS' (the author's word 25.09: «no border above or below»): the one
        // construction of the chats (MTChatListFrame), the time panel list's own law; the ground is the page's one crest. These
        // rows answer their own buttons: no swipe, no hold, no selection of the list's own.
        MontanaTimePanelList(panel: panel, rows: rows, fingerprint: rowPrint,
                             swipeLeading: { _ in [] }, swipeTrailing: { _ in [] }, swipesEnabled: false,
                             onOpen: { _ in },
                             rowContent: { AnyView(cell($0).environmentObject(store).environment(ui)) },
                             page: "p2p", fieldNames: Self.printNames, separatorRow: { _ in false })
    }

    /// Every row of the page, drawn by its name.
    @ViewBuilder private func cell(_ c: Chat) -> some View {
        if c.id == Self.headMark {
            // THE HEAD SAYS WHAT THE DRAWER NAMES (the drawer's network row, the author's word 15844): in Montana Messenger the globe is
            // the network in the time panel, so its head says the network (link 16003).
            #if MONTANA_MESSENGER
            MTPaneHead(glyph: "globe", count: MontanaNodes.liveNodes, on: node.nodeUp, line: LocalizedStringKey("P2P network"))
            #else
            MTPaneHead(glyph: "globe", count: MontanaNodes.liveNodes, on: node.nodeUp,
                       line: MTApps.vpn != nil ? LocalizedStringKey("P2P wall: the nodes this phone reaches, and the switch over them")
                                               : LocalizedStringKey("P2P network"))
            #endif
        } else if c.id == Self.p2pMark {
            p2pTab.padding(.top, 12)
        }
    }

    // ── the P2P tab: the nodes (the author's word 23.09; the VPN-nodes switch removed by his word 30.09) ──
    // «This node» (a yes/no about an external address) and «Last letter» (the hold of one letter) left the
    // tab by the author's word: the tab is the nodes.
    private var p2pTab: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                // One concept: nodes. The number beside it is how many are reachable now, the list below is who.
                HStack(spacing: 4) {
                    Text("Reachable nodes")
                    // USER-DATA: the node count.
                    Text(verbatim: "(\(MontanaNodes.liveNodes))")
                }.font(.caption).foregroundColor(.secondary).padding(.horizontal, MTLibraryRow.side).padding(.vertical, 12)
                // NODES, not doors (the author's word 26.08): one machine behind two doors is
                // ONE row of the node with its doors nested -- the count and the list finally
                // speak the same language. The node count is derived on the client from proven
                // identities, never from the length of any list.
                let live = Set(MontanaNodes.live().map { $0.label })
                let book = MontanaNodes.book()
                let heldNodes = MontanaDirect.shared.nodeIdentities(behind: live)
                let doors = MontanaNodes.list()
                // The groups: the machines the network named (15.22) -- every door under its
                // machine whatever the handshakes did -- else the machines the handshakes proved.
                let named = MontanaNodes.machines().filter { m in doors.contains { d in m.doors.contains(d) } }
                let identities: [Data] = named.isEmpty
                    ? doors.compactMap { book[$0.label]?.overlay }.reduce(into: [Data]()) { if !$0.contains($1) { $0.append($1) } }
                    : []
                let groups: [(title: String, doors: [MontanaNodes.Node], held: Bool)] = !named.isEmpty
                    ? named.map { m in
                        let ds = doors.filter { d in m.doors.contains(d) }
                        let held = ds.contains { live.contains($0.label) } || ds.contains { book[$0.label].map { heldNodes.contains($0.overlay) } ?? false }
                        return ("node " + m.id, ds, held)
                      }
                    : identities.map { ov in
                        ("node " + ov.prefix(4).map { String(format: "%02x", $0) }.joined(), doors.filter { book[$0.label]?.overlay == ov }, heldNodes.contains(ov))
                      }
                ForEach(Array(groups.enumerated()), id: \.offset) { _, g in
                    let nodeDoors = g.doors
                    VStack(alignment: .leading, spacing: 0) {
                        // USER-DATA: the machine's name from the network, or its identity prefix.
                        row(g.held ? "held" : "lost", g.held, tint: g.held ? nil : .orange) {
                            Text(verbatim: g.title)
                        }
                        ForEach(nodeDoors, id: \.label) { d in
                            // USER-DATA: the door's address and its measured speed.
                            let title = Text(verbatim: book[d.label].map { "\(d.label)  ·  \($0.ms) ms" } ?? d.label)
                            switch MontanaNodes.state(of: d, held: live, book: book, heldNodes: heldNodes) {
                            case .open:        row("open", true) { title.font(.system(size: 13)) }
                            // Not a failure and not a success: alive as the spare of a machine
                            // already reached by a faster door -- shown with its own word under the
                            // node, so both doors and their state stand in view (the author's word 07.09).
                            case .sameMachine: row("spare", true) { title.font(.system(size: 13)) }
                            case .lost:        row("lost", false, tint: .orange) { title.font(.system(size: 13)) }
                            case .silent:      row("no answer", false) { title.font(.system(size: 13)) }
                            }
                        }
                    }
                }
                let grouped = Set(groups.flatMap { $0.doors.map { $0.label } })
                let unknownDoors = doors.filter { !grouped.contains($0.label) }
                if !unknownDoors.isEmpty {
                    ForEach(unknownDoors, id: \.label) { d in
                        // USER-DATA: the door's address.
                        row("no answer", false) { Text(verbatim: d.label).font(.system(size: 13)) }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        }
    }

    /// The answer in a row is INTERFACE TEXT, not data, so it goes as a catalogue key.
    /// Here stood a `String` shown through `Text(verbatim:)`: every "yes", "open", "no answer" was
    /// shown to the person in raw English while the catalogue was fully translated, and the guard did
    /// not see it -- the literal left as a parameter instead of standing inside a view.
    private func row(_ value: LocalizedStringKey, _ ok: Bool, tint: Color? = nil,
                     @ViewBuilder title: () -> Text) -> some View {
        HStack(spacing: MTLibraryRow.gap) {
            RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.10))
                .frame(width: MTLibraryRow.face, height: MTLibraryRow.face)
                .overlay { Image(systemName: "globe").font(.system(size: 24)).foregroundColor(.secondary) }
            VStack(alignment: .leading, spacing: 4) {
                title().font(.system(size: 17, weight: .semibold)).foregroundColor(.primary).lineLimit(1)
                Text(value).font(.system(size: 16)).foregroundColor(tint ?? (ok ? .green : .red))
            }
            Spacer(minLength: 0)
        }
        .modifier(MTLibraryLine())
        .overlay(alignment: .bottom) { MTLibraryHairline() }
    }
}

/// A PANE'S OWN HEAD (the author's word 29.09): its glyph on the platform's plain glass, white, the number it counts on the badge
/// -- the people reached on the mesh, the nodes reached -- green while this phone is in, red while it is not (the mesh: the moment
/// findability is off), and one line saying what the pane is. One head for every such page: the network here, the mesh's page
/// behind its door.
struct MTPaneHead: View {
    let glyph: String
    let count: Int
    let on: Bool
    let line: LocalizedStringKey
    var body: some View {
        VStack(spacing: 12) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: glyph).font(.system(size: 26, weight: .regular)).foregroundColor(.white)
                    .frame(width: 62, height: 62)
                    .background { MTGlassCirclePlate() }
                Text("\(count)").font(.caption2.bold()).foregroundColor(.white)
                    .padding(5).background(Circle().fill(on ? Color.green : Color.red)).offset(x: 5, y: -3)
            }
            Text(line)
                .font(.footnote).foregroundColor(.secondary).multilineTextAlignment(.center)
                .padding(.horizontal, 28)
        }
        .padding(.top, 16)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12).padding(.bottom, 6)
    }
}
