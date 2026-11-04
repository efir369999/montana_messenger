import SwiftUI

// What the mesh shows a person: who is here. Joining is not an action — switching the app on makes
// this device a node, presence goes out by itself and links to reachable neighbours are built without
// being asked, the way a phone attaches to a network. So there is nothing to publish and nothing to
// connect: only the room, and who is in it.
//
// The engineering detail behind it — endpoints, ports, routing table, endpoint ages — is kept for
// diagnosing the network, not for reading every day: long-press the title to see it.

struct MontanaMeshCard: View {
    let onOpenChat: (String) -> Void
    /// The common room of everyone on the mesh (the mesh wall, 29.09): its row stands first while this phone is on the mesh.
    var onOpenRoom: () -> Void = {}
    /// Naming comes from the one place that knows: what this person called them in contacts, else what
    /// the peer calls itself, else the account address. The mesh shows people the same way the
    /// conversations do — a neighbour is not a different creature from a correspondent.
    @EnvironmentObject private var store: ChatStore
    @ObservedObject private var node = MontanaPhoneNode.shared
    @State private var showDetail = false
    @State private var tick = 0

    // One list, not two: a neighbour discovered over Wi-Fi and one in Bluetooth range are the same
    // mesh, differing only in which medium currently reaches them.
    private struct Near: Identifiable {
        let ref: String
        let live: Bool
        let transport: MontanaTransport?
        var id: String { ref }
    }
    private var nearby: [Near] {
        var seen = Set<String>()
        var out: [Near] = []
        for a in (node.peers.map { $0.neighborRef } + node.btPeers)
        where !a.isEmpty && a != node.myRef && seen.insert(a).inserted {
            out.append(Near(ref: a, live: node.hasLiveChannel(a), transport: node.transport(to: a)))
        }
        return out.sorted { ($0.live ? 0 : 1, $0.ref) < ($1.live ? 0 : 1, $1.ref) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Mesh")
                .font(.headline).foregroundColor(.primary)
                .padding(.horizontal, MTLibraryRow.side).padding(.vertical, 12)
                .onLongPressGesture(minimumDuration: montanaLongPress) { showDetail.toggle() }

            // THE COMMON ROOM FIRST (the author's word 29.09): everyone on the mesh is in it, the moment the switch is on.
            if MontanaPhoneNode.meshDiscoverable {
                Button { onOpenRoom() } label: {
                    HStack(spacing: MTLibraryRow.gap) {
                        Image(systemName: "antenna.radiowaves.left.and.right").font(.system(size: 22)).foregroundColor(.primary)
                            .frame(width: MTLibraryRow.face, height: MTLibraryRow.face)
                            .background { MTGlassCirclePlate() }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Mesh wall").font(.system(size: 17, weight: .semibold)).foregroundColor(.primary).lineLimit(1)
                            Text("Everyone on the mesh, phone to phone").font(.caption).foregroundColor(.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundColor(.secondary)
                    }
                    .modifier(MTLibraryLine())
                    .overlay(alignment: .bottom) { MTLibraryHairline() }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            if nearby.isEmpty {
                Text("No one here yet. A contact on the same Wi-Fi or within Bluetooth range appears by itself — nothing to switch on.")
                    .font(.caption).foregroundColor(.secondary).padding(.horizontal, MTLibraryRow.side).padding(.bottom, 12)
            } else {
                ForEach(nearby) { n in
                    Button { onOpenChat(n.ref) } label: {
                        HStack(spacing: MTLibraryRow.gap) {
                            AvatarCircle(photoURL: MTNameBook.displayedPhoto(n.ref), color: .gray,
                                         initial: MTNameBook.face(n.ref, title: MontanaName.of(n.ref)), size: MTLibraryRow.face, who: n.ref)
                                .overlay(MontanaHexagon().stroke(Color.white.opacity(0.45), lineWidth: 1))
                            // USER-DATA: a neighbour name.
                            Text(verbatim: MontanaName.of(n.ref))
                                .font(.system(size: 17, weight: .semibold)).foregroundColor(.primary).lineLimit(1)
                            Spacer(minLength: 4)
                            if let t = n.transport { MontanaTransportIcon(transport: t, on: n.live, size: 14) }
                            Circle().fill(n.live ? Color.green : Color.gray).frame(width: 8, height: 8)
                        }
                        .modifier(MTLibraryLine())
                        .overlay(alignment: .bottom) { MTLibraryHairline() }
                    }
                    .buttonStyle(.plain)
                }
            }

            if showDetail { detail.padding(.horizontal, MTLibraryRow.side).padding(.vertical, 12) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .id(tick)
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in tick += 1 }
    }

    // Diagnostics: what the network is actually doing. Hidden by default.
    private var detail: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider().background(Color.white.opacity(0.15))
            row("My mesh address", MontanaOverlayKey.device().map { MontanaOverlayBook.hex($0.tag, 8) } ?? "—")
            row("External address", MontanaNATService.shared.selfEndpoint() ?? MontanaNATService.shared.observedIP ?? String(localized: "not learned yet", bundle: MTLanguage.bundle))
            row("Reachable nodes", "\(node.reachableNodes)")
            row("Bluetooth", "\(node.btOn ? String(localized: "on", bundle: MTLanguage.bundle) : String(localized: "off", bundle: MTLanguage.bundle)) · links \(MontanaBLEMesh.shared.linkCount) · peers \(MontanaBLEMesh.shared.knownPeerCount) · queue \(MontanaBLEMesh.shared.queuedFragments)")
            row("Reachable now", "\(node.reachablePeers)")
            ForEach(MontanaOverlayBook.shared.allEntries().filter { !$0.ref.isEmpty }, id: \.ref) { e in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        // USER-DATA: the short form of a link.
                        Text(verbatim: MontanaP2PPeersSheet.shortEndpoint(e.ref))
                            .font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundColor(.secondary)
                        // The one word that says whether a message would move right now, and by which
                        // route — read from the same plan the send path uses.
                        // USER-DATA: a route name from the engine.
                        Text(verbatim: node.plan(to: e.ref).route)
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(node.plan(to: e.ref).isEmpty ? .red : .green)
                    }
                    ForEach(MontanaOverlayBook.shared.endpoints(ref: e.ref).indices, id: \.self) { i in
                        let ep = MontanaOverlayBook.shared.endpoints(ref: e.ref)[i]
                        // USER-DATA: an entry point address and time.
                        Text(verbatim: "\(ep.hostPort) · \(ep.source) · \(age(ep.at))")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(ep.isGlobal ? .green.opacity(0.7) : .secondary)
                    }
                }
                .padding(.top, 2)
            }
        }
    }

    private func row(_ title: LocalizedStringKey, _ value: String) -> some View {
        HStack {
            Text(title).font(.caption2).foregroundColor(.secondary)
            Spacer()
            // USER-DATA: a diagnostics line value -- a value, not view text.
            Text(verbatim: value).font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundColor(.primary)
        }
    }

    private func age(_ at: TimeInterval) -> String {
        let s = Int(Date().timeIntervalSince1970 - at)
        if s < 60 { return "\(s)s" }
        if s < 3600 { return "\(s / 60)m" }
        return "\(s / 3600)h"
    }
}

/// THE MESH DOOR'S PROTOCOL SIDE (MTApps.mesh): the radio (MontanaBLEMesh), the room (MTMeshRoom) and the card above, behind one
/// door, so the shared code names none of them and Montana Messenger builds without them.
final class MTMeshAppDoor: MTMeshDoor {
    func setDiscoverable(_ on: Bool) { MontanaBLEMesh.shared.setDiscoverable(on) }
    func start() { MontanaBLEMesh.shared.start() }
    func powerDown() { MontanaBLEMesh.shared.powerDown() }
    var linkCount: Int { MontanaBLEMesh.shared.linkCount }
    var knownPeerCount: Int { MontanaBLEMesh.shared.knownPeerCount }
    var queuedFragments: Int { MontanaBLEMesh.shared.queuedFragments }
    func send(to conv: String, envelope: Data) -> Bool { MontanaBLEMesh.shared.send(to: conv, envelope: envelope) }
    func sendBlob(to conv: String, blobId: String, sealed: Data) -> Bool {
        MontanaBLEMesh.shared.sendBlob(to: conv, blobId: blobId, sealed: sealed)
    }
    func say(_ text: String) { MTMeshRoom.say(text) }
    @MainActor func share(_ row: Message) -> Bool { MTMeshRoom.share(row) }
    func name(of ref: String?) -> String? { MTMeshRoom.name(of: ref) }
    @MainActor func page(panel: MontanaTimePanel, onOpenChat: @escaping (String) -> Void) -> AnyView {
        AnyView(MTMeshWallPage(panel: panel, onOpenChat: onOpenChat))
    }
    func advertise(port: UInt16, directPort: UInt16) { MontanaBonjour.shared.advertise(port: port, directPort: directPort) }
    func stopAdvertising() { MontanaBonjour.shared.stopAdvertising() }
    func browse(timeout: TimeInterval) -> [MontanaPeer] { MontanaBonjour.shared.browse(timeout: timeout) }
    var announceAccepted: Bool { MontanaBonjour.shared.announceAccepted }
    func openRouterDoor() { MontanaPortMap.open() }
    var routerDoor: (open: Bool, external: String, port: UInt16) { MontanaPortMap.state }
}

/// THE MESH WALL (the pane .mesh, drawn through MTMeshDoor.page; link 15898): a page under the time panel as the P2P wall is
/// (NetworkTabView), its rows -- the head, my card, who is here -- each printed by what it draws. It stood inside NetworkTabView
/// until 15898, so its words and its switch were compiled into Montana Messenger; now only the Protocol holds it.
struct MTMeshWallPage: View {
    @EnvironmentObject private var store: ChatStore
    @Environment(UIState.self) private var ui
    let panel: MontanaTimePanel
    let onOpenChat: (String) -> Void            // (montana address) -> open the normal chat, over the tabs
    @ObservedObject private var node = MontanaPhoneNode.shared
    @AppStorage("mt.mesh.discoverable") private var meshDiscoverable = false   // OFF at birth -- the switch itself raises the system prompt

    private static let headMark = "net:head"
    private static let meMark = "mesh:me"
    private static let nearMark = "mesh:near"
    private static func chatRow(_ id: String) -> Chat { Chat(name: id, lastMessage: "", time: "", unread: 0, status: "", convId: id) }
    private var rows: [Chat] { [Self.headMark, Self.meMark, Self.nearMark].map(Self.chatRow) }
    private var near: Int { node.peers.count + node.btPeers.count }

    private func rowPrint(_ c: Chat) -> [Int] {
        func p<T: Hashable>(_ v: T) -> Int { var h = Hasher(); h.combine(v); return h.finalize() }
        var out = [p(c.id)] + Array(repeating: 0, count: NetworkTabView.printNames.count - 1)
        if c.id == Self.headMark {
            out[4] = p(near)
            out[8] = p([node.nodeUp, meshDiscoverable])
        } else if c.id == Self.meMark {
            out[8] = p([E2E.myDisplayName(), meshDiscoverable ? "1" : "0"])
        }
        return out
    }

    var body: some View {
        let _ = MTFrameMeter.shared.body("network")   // the page's passes while a motion is measured
        MontanaTimePanelList(panel: panel, rows: rows, fingerprint: rowPrint,
                             swipeLeading: { _ in [] }, swipeTrailing: { _ in [] }, swipesEnabled: false,
                             onOpen: { _ in },
                             rowContent: { AnyView(cell($0).environmentObject(store).environment(ui)) },
                             page: "mesh", fieldNames: NetworkTabView.printNames, separatorRow: { _ in false })
    }

    @ViewBuilder private func cell(_ c: Chat) -> some View {
        if c.id == Self.headMark {
            MTWallHead(glyph: "antenna.radiowaves.left.and.right", count: near, on: node.nodeUp && meshDiscoverable,
                       line: LocalizedStringKey("Mesh wall: the people around you, phone to phone, with no server between"))
        } else if c.id == Self.meMark {
            meCard.padding(.horizontal, MTLibraryRow.side).padding(.top, 12)   // off the edges as the posts (26.09)
        } else if c.id == Self.nearMark {
            MontanaMeshCard(onOpenChat: onOpenChat,
                            onOpenRoom: { ui.openChat(Chat(name: meshRoomKey, lastMessage: "", time: "", unread: 0, status: "")) })
        }
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
                                 set: { meshDiscoverable = $0; MontanaPhoneNode.meshDiscoverable = $0 })) {
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
