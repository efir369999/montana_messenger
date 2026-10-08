import SwiftUI
import UIKit
import MontanaBindings

/// P2P network test (serverless self-host). The node comes up ITSELF when the app opens —
/// the screen only reflects status and shows the card automatically. There is no manual "connect".
/// Sending: paste the peer's card (still manual for now; mDNS auto-discovery is the next step).
// Nearby-devices picker (green Wi-Fi indicator). Tapping a device opens the SAME chat
// as scanning their QR / adding by address — messages then travel over the Wi-Fi mesh (no server).
struct MontanaP2PPeersSheet: View {
    @EnvironmentObject private var store: ChatStore
    let onOpenChat: (String) -> Void            // (montana address) -> open the normal chat
    @ObservedObject private var node = MontanaP2PNode.shared
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


// THE NETWORK UNDER THE TIME PANEL (the author's word 25.09: «make the network page a full page under the time panel, with
// no border above or below, as the chats, the calls, the contacts and the feed are»): a page of the finger's row, chosen as every
// page is -- by the globe on the bar, by the drawer's row, by a stroke -- with the puck under the globe. It stands on the one
// container of the pages under the bar (MontanaTimePanelList): the panel's head at its head, its rows running on to the screen's
// edges. THE VPN IS ITS OWN APP (the author's word 08.10.2026 00:5x MSK: «extract the VPN wholly from Montana and Business -- it
// is a separate app now, Montana VPN»): this page carries two walls -- the mesh, the people around phone to phone, and the P2P,
// the nodes this phone reaches; the globe opens the P2P wall. Every row is printed by what it draws, so a change moves its own
// row alone (the calls' law, rowPrint).
struct NetworkTabView: View {
    @EnvironmentObject private var store: ChatStore
    @Environment(UIState.self) private var ui
    let panel: MontanaTimePanel
    /// WHICH WALL THIS PAGE IS (the author's word 29.09: «the network is disbanded -- the VPN wall, the mesh wall and the P2P wall
    /// are three applications»): the pane it stands in names it. The VPN wall left with the VPN for its own app (08.10.2026).
    let wall: UIState.Pane
    var query = ""   // the head's word: neither wall carries rows it narrows
    let onOpenChat: (String) -> Void            // (montana address) -> open the normal chat, over the tabs
    @ObservedObject private var node = MontanaP2PNode.shared
    private var selected: Int { wall == .mesh ? 1 : 2 }   // 1 the mesh wall, 2 the P2P wall
    @AppStorage("mt.mesh.discoverable") private var meshDiscoverable = false   // OFF at birth -- the switch itself raises the system prompt

    // THE ROWS OF THE PAGE, each named by what it is: the head, the mesh's two cards, the nodes. The name is the row's identity
    // for the list's differences (Chat.id).
    private static let headMark = "net:head"
    private static let meshMeMark = "mesh:me"
    private static let meshNearMark = "mesh:near"
    private static let p2pMark = "net:p2p"
    private static func chatRow(_ id: String) -> Chat { Chat(name: id, lastMessage: "", time: "", unread: 0, status: "", convId: id) }

    /// The rows, in the page's order: the head first; on the mesh wall the two cards; on the P2P wall the nodes.
    private var rows: [Chat] {
        var out = [Self.chatRow(Self.headMark)]
        if selected == 1 {
            out += [Self.chatRow(Self.meshMeMark), Self.chatRow(Self.meshNearMark)]
        } else {
            out.append(Self.chatRow(Self.p2pMark))
        }
        return out
    }
    /// The print's fields by name, in its order -- the diary names a changed row's field by them. One shape for every kind of
    /// row, so a row's old and new prints always read the same fields; a field a kind does not draw stays zero.
    private static let printNames = ["id", "tab", "count", "word"]
    private func rowPrint(_ c: Chat) -> [Int] {
        func p<T: Hashable>(_ v: T) -> Int { var h = Hasher(); h.combine(v); return h.finalize() }
        var out = [p(c.id)] + Array(repeating: 0, count: Self.printNames.count - 1)
        if c.id == Self.headMark {
            out[1] = p(selected)
            out[2] = p([node.peers.count + node.btPeers.count, MontanaNodes.liveNodes])
            out[3] = p([node.p2pUp, meshDiscoverable])
        } else if c.id == Self.meshMeMark {
            out[3] = p([E2E.myDisplayName(), meshDiscoverable ? "1" : "0"])
        } else if c.id == Self.p2pMark {
            out[2] = p([MontanaNodes.liveNodes, MontanaNodes.list().count])
            out[3] = p(MontanaNodes.live().map { $0.label } + MontanaNodes.list().map { $0.label })
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
                             page: selected == 1 ? "mesh" : "p2p", fieldNames: Self.printNames)
    }

    /// Every row of the page, drawn by its name.
    @ViewBuilder private func cell(_ c: Chat) -> some View {
        if c.id == Self.headMark {
            head
        } else if c.id == Self.meshMeMark {
            meCard.padding(.horizontal, MTLibraryRow.side).padding(.top, 12)   // off the edges as the posts (26.09)
        } else if c.id == Self.meshNearMark {
            MontanaMeshCard(onOpenChat: { ref in onOpenChat(ref) },
                            onOpenRoom: { ui.openChat(Chat(name: meshRoomKey, lastMessage: "", time: "", unread: 0, status: "")) })
        } else if c.id == Self.p2pMark {
            p2pTab.padding(.top, 12)
        }
    }

    /// The head of the page: the wall's own head.
    private var head: some View {
        VStack(spacing: 16) { wallHead }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12).padding(.bottom, 6)
    }

    /// A WALL'S OWN HEAD (the author's word 29.09): its glyph on the platform's plain glass, the number it counts on the badge --
    /// the people reached on the mesh, the nodes reached -- green while this phone is in, red while it is not (the mesh: the
    /// moment findability is off), and one line saying what the wall is.
    private var wallHead: some View {
        let mesh = selected == 1
        let on = mesh ? (node.p2pUp && meshDiscoverable) : node.p2pUp
        let count = mesh ? node.peers.count + node.btPeers.count : MontanaNodes.liveNodes
        return VStack(spacing: 12) {
            ZStack(alignment: .topTrailing) {
                symbol(selected, chosen: false)
                    .frame(width: 62, height: 62)
                    .background { MTGlassCirclePlate() }
                Text("\(count)").font(.caption2.bold()).foregroundColor(.white)
                    .padding(5).background(Circle().fill(on ? Color.green : Color.red)).offset(x: 5, y: -3)
            }
            Text(mesh ? LocalizedStringKey("Mesh wall: the people around you, phone to phone, with no server between")
                      : LocalizedStringKey("P2P wall: the nodes this phone reaches"))
                .font(.footnote).foregroundColor(.secondary).multilineTextAlignment(.center)
                .padding(.horizontal, 28)
        }
        .padding(.top, 16)
    }

    // SSOT canonical transport icon -- same source as the chats header and bubbles; white by default, the platform's blue
    // on the chosen tab (the author's word 25.09).
    @ViewBuilder private func symbol(_ idx: Int, chosen: Bool) -> some View {
        // P2P: the globe. Mesh: the antenna -- one icon for the network itself.
        let tint = chosen ? MontanaOctagon.platformBlue : Color.white
        if idx == 2 {
            Image(systemName: "globe")
                .font(.system(size: 26, weight: .regular))
                .foregroundColor(tint)
        } else {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 26, weight: .regular))
                .foregroundColor(tint)
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

    // What the people around actually see, said honestly.
    //
    // This card used to show a person their own reference under the words «how others see you»,
    // which taught them they had an address and invited them to hand it out. They have none: the
    // reference of a correspondence is computed on the device, never leaves it, and reaches nobody
    // who holds it. What the people around see is a machine speaking this protocol -- and, of those
    // who already share a secret with it, that it is here.
    private var meCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("How others see you").font(.caption).foregroundColor(.secondary)
            HStack(spacing: 12) {
                Circle().fill(Color.white.opacity(0.10)).frame(width: MTLibraryRow.face, height: MTLibraryRow.face)
                    // USER-DATA: the first letter of a person's name.
                    .overlay(Text(verbatim: String(E2E.myDisplayName().prefix(1)).uppercased())
                                .font(.system(size: 18, weight: .semibold)).foregroundColor(.white))
                VStack(alignment: .leading, spacing: 2) {
                    // USER-DATA: a person's name.
                    Text(verbatim: E2E.myDisplayName())
                        .font(.system(size: 15, weight: .semibold)).foregroundColor(.primary)
                    Text("Only people you already share a conversation with can tell it is you.")
                        .font(.system(size: 11)).foregroundColor(.secondary)
                }
                Spacer()
            }
            Toggle(isOn: Binding(get: { meshDiscoverable },
                                 set: { meshDiscoverable = $0; MontanaP2PNode.meshDiscoverable = $0 })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Findable on the mesh").font(.system(size: 14, weight: .medium))
                    Text("Off: this device announces itself nowhere and carries nothing for anybody.")
                        .font(.caption2).foregroundColor(.secondary)
                }
            }
            .tint(.green)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12)
    }
}
