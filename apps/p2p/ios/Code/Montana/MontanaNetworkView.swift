import SwiftUI
import UIKit
import MontanaBindings

// THE NETWORK UNDER THE TIME PANEL (the author's word 25.09: «make the network page a full page under the time panel, with
// no border above or below, as the chats, the calls, the contacts and the feed are»): a page of the finger's row, chosen as every
// page is -- by the globe on the bar, by the drawer's row, by a stroke -- with the puck under the globe. It stands on the one
// container of the pages under the bar (MontanaTimePanelList): the panel's head at its head, its rows running on to the screen's
// edges. THE VPN AND THE MESH ARE APPS OF THEIR OWN (the author's words 08.10.2026: «extract the VPN wholly from Montana and
// Business -- it is a separate app now, Montana VPN»; the mesh's switch «nowhere -- only in the Mesh app»): this page is the P2P
// wall, the nodes this phone reaches. Every row is printed by what it draws, so a change moves its own row alone (the calls'
// law, rowPrint).
struct NetworkTabView: View {
    @EnvironmentObject private var store: ChatStore
    @Environment(UIState.self) private var ui
    let panel: MontanaTimePanel
    @ObservedObject private var node = MontanaP2PNode.shared

    // THE ROWS OF THE PAGE, each named by what it is: the head, the nodes. The name is the row's identity for the list's
    // differences (Chat.id).
    private static let headMark = "net:head"
    private static let p2pMark = "net:p2p"
    private static func chatRow(_ id: String) -> Chat { Chat(name: id, lastMessage: "", time: "", unread: 0, status: "", convId: id) }

    private var rows: [Chat] { [Self.chatRow(Self.headMark), Self.chatRow(Self.p2pMark)] }
    /// The print's fields by name, in its order -- the diary names a changed row's field by them. One shape for every kind of
    /// row, so a row's old and new prints always read the same fields; a field a kind does not draw stays zero.
    private static let printNames = ["id", "count", "word"]
    private func rowPrint(_ c: Chat) -> [Int] {
        func p<T: Hashable>(_ v: T) -> Int { var h = Hasher(); h.combine(v); return h.finalize() }
        var out = [p(c.id)] + Array(repeating: 0, count: Self.printNames.count - 1)
        if c.id == Self.headMark {
            out[1] = p(MontanaNodes.liveNodes)
            out[2] = p(node.p2pUp)
        } else if c.id == Self.p2pMark {
            out[1] = p([MontanaNodes.liveNodes, MontanaNodes.list().count])
            out[2] = p(MontanaNodes.live().map { $0.label } + MontanaNodes.list().map { $0.label })
        }
        return out
    }

    var body: some View {
        let _ = MTFrameMeter.shared.body("network")   // the page's passes while a motion is measured
        // THE ROWS RUN ON TO THE SCREEN'S EDGES, AS THE CHATS' (the author's word 25.09: «no border above or below»): the one
        // construction of the chats (MTChatListFrame), the time panel list's own law; the ground is the page's one crest.
        MontanaTimePanelList(panel: panel, rows: rows, fingerprint: rowPrint,
                             swipeLeading: { _ in [] }, swipeTrailing: { _ in [] },
                             swipesEnabled: false,
                             onOpen: { _ in },
                             rowContent: { AnyView(cell($0).environmentObject(store).environment(ui)) },
                             page: "p2p", fieldNames: Self.printNames)
    }

    /// Every row of the page, drawn by its name.
    @ViewBuilder private func cell(_ c: Chat) -> some View {
        if c.id == Self.headMark {
            head
        } else if c.id == Self.p2pMark {
            p2pTab.padding(.top, 12)
        }
    }

    /// THE WALL'S OWN HEAD (the author's word 29.09): the globe on the platform's plain glass, the nodes reached on the badge --
    /// green while this phone is in, red while it is not -- and one line saying what the wall is.
    private var head: some View {
        VStack(spacing: 12) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "globe")
                    .font(.system(size: 26, weight: .regular))
                    .foregroundColor(.white)
                    .frame(width: 62, height: 62)
                    .background { MTGlassCirclePlate() }
                Text("\(MontanaNodes.liveNodes)").font(.caption2.bold()).foregroundColor(.white)
                    .padding(5).background(Circle().fill(node.p2pUp ? Color.green : Color.red)).offset(x: 5, y: -3)
            }
            Text("P2P wall: the nodes this phone reaches")
                .font(.footnote).foregroundColor(.secondary).multilineTextAlignment(.center)
                .padding(.horizontal, 28)
        }
        .padding(.top, 16)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12).padding(.bottom, 6)
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
                let heldNodes = MontanaP2PDirect.shared.nodeIdentities(behind: live)
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
