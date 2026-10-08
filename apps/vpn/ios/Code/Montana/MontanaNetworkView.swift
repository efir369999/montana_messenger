import SwiftUI
import UIKit
import Security
import UniformTypeIdentifiers
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
// no border above or below, as the chats, the calls, the contacts and the feed are»): a page of the finger's row
// (UIState.Pane.network), chosen as every page is -- by the globe on the bar, by the drawer's row, by a stroke -- with the puck
// under the globe. It stands on the one container of the pages under the bar (MontanaTimePanelList): the panel's head at its
// head, its rows running on to the screen's edges under the panel and the home strip, the page's own crest ground. Everything
// the page shows is a row of that list -- the head (the three tabs, the power, the timer), each plan's header, each server, the
// hand-added servers' header, the mesh's two cards, the nodes -- printed by what it draws, so a ping, a fold, a pin or the
// tunnel's word moves its own row alone (the calls' law, rowPrint). The tap, the hold and the swipe are the container's own
// (15.26, 16.09): a tap on a server chooses it, a hold opens its menu, the swipe from the left measures it and the swipe from the
// right pins or deletes it. The plus stands bottom right as the music's plus and the chats' write do; the page searches itself
// as the music and the feed do. The page over the tabs it was (NavigationView, a toolbar, a close, a List) is gone with the
// page's rebirth at every touch of the globe -- the class of 1938, closed for the pages under the bar on 25.09.
/// THE NETWORK PAGE'S INDEX OF ITS SERVERS (28.09): built once per write of the list -- each id spelled once, each server found
/// by its id in one step, each section's servers and their ids in the list's own order.
struct MTServerBook {
    let servers: [MontanaVPNConfig]
    let byId: [String: MontanaVPNConfig]
    let byPlan: [String: [MontanaVPNConfig]]
    let planIds: [String: [String]]
    let manual: [MontanaVPNConfig]
    let manualIds: [String]
    init(_ list: [MontanaVPNConfig]) {
        servers = list
        var ids: [String: MontanaVPNConfig] = [:]
        var plans: [String: [MontanaVPNConfig]] = [:]
        var planIdList: [String: [String]] = [:]
        var hand: [MontanaVPNConfig] = []
        var handIds: [String] = []
        ids.reserveCapacity(list.count)
        for c in list {
            let id = c.id
            if ids[id] == nil { ids[id] = c }   // the first of two equal ids answers, as the walk it replaces did
            if let plan = c.subscription {
                plans[plan, default: []].append(c)
                planIdList[plan, default: []].append(id)
            } else {
                hand.append(c)
                handIds.append(id)
            }
        }
        byId = ids; byPlan = plans; planIds = planIdList; manual = hand; manualIds = handIds
    }
}

struct NetworkTabView: View {
    @EnvironmentObject private var store: ChatStore
    @Environment(UIState.self) private var ui
    let panel: MontanaTimePanel
    /// WHICH WALL THIS PAGE IS (the author's word 29.09: «the network is disbanded -- the VPN wall, the mesh wall and the P2P wall
    /// are three applications»): the pane it stands in names it; the three tab buttons of the network page are gone.
    let wall: UIState.Pane
    /// THE PAGE'S OWN SEARCH (the music's and the feed's law): the word at the head narrows the servers -- by their name, host,
    /// protocol, transport and wrapper -- in the platform's own comparison (localizedStandardContains: letter case and marks
    /// aside); nothing leaves the phone and no results stand over the rows. A plan whose servers match shows them, folded or
    /// not; a plan without a match leaves the page until the word is gone.
    var query = ""
    let onOpenChat: (String) -> Void            // (montana address) -> open the normal chat, over the tabs
    @ObservedObject private var node = MontanaP2PNode.shared
    private var selected: Int { wall == .mesh ? 1 : (wall == .p2p ? 2 : 0) }   // 0 the VPN wall, 1 the mesh wall, 2 the P2P wall
    @AppStorage("mt.mesh.discoverable") private var meshDiscoverable = false   // OFF at birth -- the switch itself raises the system prompt
    @StateObject private var tunnel = MontanaVPNTunnel.shared
    @ObservedObject private var pay = MTVPNPay.shared
    // THE PAGE IS BORN HOLDING WHAT IT SHOWS (the author's word 22.09: the globe thought before it opened). The store hands the
    // list over from memory, so the very first body already has its rows -- and the page stays built in the row once looked at
    // or warmed after the launch (25.09): the globe's tap moves the puck, and nothing is born.
    @State private var book = MTServerBook(MontanaVPNStore.load())
    /// THE SERVERS ARE READ THROUGH THEIR ONE INDEX (28.09, the fleet's diaries): a server's id is spelled anew from five of its
    /// fields at every reading (MontanaVPNConfig.id), and every pass of this page looked each row's server up by walking the whole
    /// list -- 397 rows on T1, 157 thousand spellings a pass, ~220 ms of the main thread each; 11 s of every 30 while the page stood
    /// (list_work ms=11089.7 rows=397), and the iPhone 17 Pro Max ran hot under the same page. A write of the list builds the index
    /// once; every reading of a pass is a step in it.
    private var vpnServers: [MontanaVPNConfig] {
        get { book.servers }
        nonmutating set { book = MTServerBook(newValue) }
    }
    // The chosen row is the tunnel owner's published word (MontanaVPNTunnel.selectedId), not the store's dotted key: a
    // choice made by the app itself -- a dead road giving way -- never reached the key's observation (25.09).
    @State private var vpnNote: LocalizedStringKey? = nil
    @State private var showVPNScanner = false
    @State private var showVPNManual = false           // the form of a server by hand (MontanaVPNManualEntry)
    @State private var showVPNSubscription = false     // the plan's link, typed or pasted into the platform's own alert
    @State private var vpnSubscriptionLink = ""
    @State private var showVPNFile = false             // the platform's file picker: a profile file of any shape
    @State private var vpnBusy = false
    @ObservedObject private var delays = MontanaVPNDelayBook.shared     // what every server last answered, drawn always (29.09)
    @ObservedObject private var fresh = MontanaVPNFreshener.shared      // a plan loaded again behind the page moves its generation
    @ObservedObject private var pingLine = MontanaVPNPingLine.shared    // the section's gauge spins while its rows are in flight (29.09)
    @ObservedObject private var road = MTVPNWhitelistRoad.shared         // the VPN wall's word under the permitted list (30.09)
    @State private var renameServer: MontanaVPNConfig? = nil
    @State private var renameText = ""
    @State private var vpnListExpanded = !MontanaVPNPlans.manualFolded   // the hand-added section's fold, remembered as a plan's is
    @State private var manualPinnedAt: Double? = MontanaVPNPlans.manualPinnedAt   // the hand-added section's pin, held as the plans' are
    @State private var plans: [MontanaVPNPlan] = MontanaVPNPlans.ordered()   // each carries its own fold and pin
    @State private var loadingPlan: String? = nil     // the link being fetched right now ("*" -- every plan)

    // THE ROWS OF THE PAGE, each named by what it is: the head, a plan's header, the hand-added header, a server, the word for
    // nothing found, the mesh's two cards, the nodes. The name is the row's identity for the list's differences (Chat.id).
    private static let headMark = "net:head"
    private static let planMark = "plan:"
    private static let manualMark = "net:manual"
    private static let serverMark = "srv:"
    private static let noneMark = "net:none"
    private static let meshMeMark = "mesh:me"
    private static let meshNearMark = "mesh:near"
    private static let p2pMark = "net:p2p"
    private static func chatRow(_ id: String) -> Chat { Chat(name: id, lastMessage: "", time: "", unread: 0, status: "", convId: id) }

    private var word: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private func matches(_ c: MontanaVPNConfig) -> Bool {
        word.isEmpty || [c.name, c.host, c.proto.rawValue, c.network, c.security].contains { $0.localizedStandardContains(word) }
    }
    /// The ids of a section's servers the page shows: all of them, or the ones the word names (the index holds the ids spelled once).
    private func shownIds(_ list: [MontanaVPNConfig], _ ids: [String]) -> [String] {
        word.isEmpty ? ids : zip(list, ids).filter { matches($0.0) }.map { $0.1 }
    }
    /// A plan's rows: its header, and its servers unless the arrow folded them -- a word at the head unfolds what it finds.
    private func planRows(_ plan: MontanaVPNPlan) -> [Chat] {
        let found = shownIds(servers(of: plan), book.planIds[plan.url] ?? [])
        if !word.isEmpty {
            guard !found.isEmpty || plan.shownTitle.localizedStandardContains(word) else { return [] }
            return [Self.chatRow(Self.planMark + plan.url)] + found.map { Self.chatRow(Self.serverMark + $0) }
        }
        return [Self.chatRow(Self.planMark + plan.url)] + (plan.folded != true ? found.map { Self.chatRow(Self.serverMark + $0) } : [])
    }
    /// The rows, in the page's order: the head first; on the VPN tab every plan as a section of its own and the hand-added
    /// servers where their pin puts them; on the mesh tab the two cards; on the P2P tab the nodes.
    private var rows: [Chat] {
        var out = [Self.chatRow(Self.headMark)]
        switch selected {
        case 0:
            // The hand-added section is the person's own: it stands among their own plans where its pin puts it (the author's word
            // 24.09: it is pinned from its menu as a plan is), unpinned after them, and above every wall (30.09). The place is named
            // once, by the plans.
            let slot = MontanaVPNPlans.manualSlot(in: plans, pinnedAt: manualPinnedAt)
            for plan in plans.prefix(slot) { out += planRows(plan) }
            let manual = shownIds(manualServers, book.manualIds)
            if !manual.isEmpty {
                out.append(Self.chatRow(Self.manualMark))
                if vpnListExpanded || !word.isEmpty { out += manual.map { Self.chatRow(Self.serverMark + $0) } }
            }
            for plan in plans.dropFirst(slot) { out += planRows(plan) }
            if !word.isEmpty, out.count == 1 { out.append(Self.chatRow(Self.noneMark)) }
        case 1:
            out += [Self.chatRow(Self.meshMeMark), Self.chatRow(Self.meshNearMark)]
        default:
            out.append(Self.chatRow(Self.p2pMark))
        }
        return out
    }
    /// A server row's id: the row's name less its mark -- the id the index spelled once.
    private func serverId(_ c: Chat) -> String? {
        c.id.hasPrefix(Self.serverMark) ? String(c.id.dropFirst(Self.serverMark.count)) : nil
    }
    private func server(_ c: Chat) -> MontanaVPNConfig? { serverId(c).flatMap { book.byId[$0] } }
    private func plan(_ c: Chat) -> MontanaVPNPlan? {
        guard c.id.hasPrefix(Self.planMark) else { return nil }
        let url = String(c.id.dropFirst(Self.planMark.count))
        return plans.first { $0.url == url }
    }
    /// The print's fields by name, in its order -- the diary names a changed row's field by them. One shape for every kind of
    /// row, so a row's old and new prints always read the same fields; a field a kind does not draw stays zero.
    private static let printNames = ["id", "tab", "tunnel", "line", "count", "fold", "pin", "moment", "word", "selected", "ping"]
    private func rowPrint(_ c: Chat) -> [Int] {
        func p<T: Hashable>(_ v: T) -> Int { var h = Hasher(); h.combine(v); return h.finalize() }
        var out = [p(c.id)] + Array(repeating: 0, count: Self.printNames.count - 1)
        if c.id == Self.headMark {
            out[1] = p(selected)
            out[2] = p([tunnel.status.rawValue, tunnel.isOn ? 1 : 0, Int(tunnel.connectedAt?.timeIntervalSince1970 ?? 0)])
            out[3] = p([tunnel.lastError, tunnel.backgroundError, String(describing: vpnNote), vpnBusy ? "1" : "0", road.line ?? ""])
            out[4] = p([vpnServers.count, plans.count, node.peers.count + node.btPeers.count, MontanaNodes.liveNodes])
            out[8] = p([node.p2pUp, meshDiscoverable, vpnServers.isEmpty && plans.isEmpty])
        } else if let plan = plan(c) {
            out[3] = p([plan.lastError ?? "", String(plan.unsupported ?? 0)])
            out[4] = p(servers(of: plan).count)
            out[5] = p(plan.folded == true)
            out[6] = p(plan.pinnedAt ?? 0)
            out[7] = p(plan.updatedAt)
            out[8] = p([plan.shownTitle, String(plan.download ?? 0), String(plan.upload ?? 0), String(plan.total ?? 0), String(plan.expire ?? 0)])
            out[10] = p(loadingPlan == plan.url || loadingPlan == "*")
        } else if c.id == Self.manualMark {
            out[4] = p(manualServers.count)
            out[5] = p(vpnListExpanded)
            out[6] = p(manualPinnedAt ?? 0)
            out[8] = p(plans.isEmpty)
        } else if let id = serverId(c), let cfg = book.byId[id] {
            out[8] = p([cfg.name, cfg.proto.rawValue, cfg.network, cfg.security])
            out[9] = p(id == tunnel.selectedId)
            let e = delays.entries[id]
            out[10] = p([e?.ms ?? -1, e?.err == nil ? 0 : 1, e == nil ? 0 : 1, (e?.age ?? 0) < MontanaVPNDelayBook.stale ? 0 : 1])
        } else if c.id == Self.meshMeMark {
            out[8] = p([E2E.myDisplayName(), meshDiscoverable ? "1" : "0"])
        } else if c.id == Self.p2pMark {
            out[4] = p([MontanaNodes.liveNodes, MontanaNodes.list().count])
            out[8] = p(MontanaNodes.live().map { $0.label } + MontanaNodes.list().map { $0.label })
        }
        return out
    }

    var body: some View {
        let _ = MTFrameMeter.shared.body("network")   // the page's passes while a motion is measured
        // THE ROWS RUN ON TO THE SCREEN'S EDGES, AS THE CHATS' (the author's word 25.09: «no border above or below»): the one
        // construction of the chats (MTChatListFrame), the time panel list's own law; the ground is the page's one crest.
        MontanaTimePanelList(panel: panel, rows: rows, fingerprint: rowPrint,
                             swipeLeading: swipeLeading, swipeTrailing: swipeTrailing,
                             swipesEnabled: selected == 0,
                             onOpen: tap,
                             rowContent: { AnyView(cell($0).environmentObject(store).environment(ui)) },
                             onHold: hold, holdsRow: { server($0) != nil },   // a hold begins on a server alone: the head's and the headers' buttons keep their presses
                             page: selected == 0 ? "vpn" : (selected == 1 ? "mesh" : "p2p"), fieldNames: Self.printNames, separatorRow: { server($0) != nil })
            // THE PLUS, bottom right, as the music's plus and the chats' write (the author's word 23.09 for the music): the
            // toolbar's menu of the page over the tabs stood here before -- paste, scan, enter by hand, update the plans.
            .mtPageAction(shown: selected == 0) { plus }
            .sheet(isPresented: $showVPNScanner) {
                NavigationView {
                    QRScannerView { code in showVPNScanner = false; addVPNText(code, from: "scan") }
                        .ignoresSafeArea()
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .principal) { Text("Scan QR code").font(.headline) }
                            ToolbarItem(placement: .cancellationAction) { MontanaCloseMark { showVPNScanner = false } }
                        }
                }
            }
            // THE FIVE ROADS OF THE AUTHOR'S EXAMPLE MENU AND THE FILE (29.09): the plan's link in the platform's own alert, the
            // form of a server by hand as a sheet, the platform's file picker for a profile of any shape.
            .sheet(isPresented: $showVPNManual) {
                MontanaVPNManualEntry { cfg in addVPNServers([cfg], from: "form", form: "form") }
            }
            .alert("Subscription URL", isPresented: $showVPNSubscription) {
                TextField("Subscription link", text: $vpnSubscriptionLink)
                    .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                Button("Add subscription") { addVPNText(vpnSubscriptionLink, from: "typed"); vpnSubscriptionLink = "" }
                Button("Cancel", role: .cancel) { vpnSubscriptionLink = "" }
            }
            .fileImporter(isPresented: $showVPNFile, allowedContentTypes: [.item], allowsMultipleSelection: true) { importVPNFiles($0) }
            .alert("Rename", isPresented: Binding(get: { renameServer != nil }, set: { if !$0 { renameServer = nil; renameText = "" } })) {
                TextField("Name", text: $renameText)
                Button("Save") { doRename() }
                Button("Cancel", role: .cancel) { renameServer = nil; renameText = "" }
            }
            // THE PAGE OPENS BY THE PANE'S CHOICE (the author's word 24.09: one «page», one «list», one question to the tunnel
            // per touch of the globe). The page stands built in the row before it is looked at (25.09), so its appearance is
            // not its opening -- the pane's choice is, once per choice: say how long the choice took from the globe's touch,
            // read the tunnel, read the list.
            .onChange(of: ui.pane, initial: true) { _, p in
                guard p == .vpn else { return }   // the VPN wall's opening; the mesh and the P2P walls read nothing at theirs
                let open = MontanaVPNOpen.msSinceTap()
                vpnMark("page", "plans=\(plans.count) manual=\(manualServers.count) all=\(vpnServers.count) tunnel=\(tunnel.statusText) open_ms=\(open.map(String.init) ?? "-")")
                Task { await tunnel.load() }
                reloadVPN()
                // The opening loads and asks nothing (the author's word 30.09: an update at a press of the hand or once an hour).
            }
            .onChange(of: fresh.generation) { _, _ in reloadVPN() }
    }

    /// THE PLUS: the system's own menu on the page's octagon plate (the chats' write button, one to one) -- the road every
    /// exit node comes in by (the author's example menu 29.09): the plan's link, the clipboard, the camera, a file, the form,
    /// and the JSON of the chosen server out.
    private var plus: some View {
        Menu {
            Button { showVPNSubscription = true } label: { Label("Subscription URL", systemImage: "link.badge.plus") }
            Button { pasteVPN() } label: { Label("Paste from clipboard", systemImage: "doc.on.clipboard") }
            Button { showVPNScanner = true } label: { Label("Scan QR code", systemImage: "qrcode.viewfinder") }
            Button { showVPNFile = true } label: { Label("Import from file", systemImage: "doc.badge.plus") }
            Button { showVPNManual = true } label: { Label("Manual entry", systemImage: "square.and.pencil") }
            Button { copyJSON(selectedServer) } label: { Label("Copy JSON", systemImage: "curlybraces") }
                .disabled(selectedServer.map { $0.proto == .unsupported } ?? true)
            if !plans.isEmpty {   // asked of what the page holds: a body never reads storage
                Button { refreshSubscriptions() } label: { Label("Update subscriptions", systemImage: "arrow.clockwise") }
            }
        } label: {
            Image(systemName: "plus").font(.system(size: 27, weight: .medium)).foregroundColor(MontanaOctagon.barGlyph)
        }
        .menuStyle(.button)
        .buttonStyle(.montanaOctagon(square: true, bar: true))
        .accessibilityLabel(Text("Add exit node"))
    }

    /// Every row of the page, drawn by its name.
    @ViewBuilder private func cell(_ c: Chat) -> some View {
        if c.id == Self.headMark {
            head
        } else if c.id == Self.noneMark {
            Text("Nothing found").foregroundColor(.gray).frame(maxWidth: .infinity).padding(.vertical, 24)
        } else if c.id == Self.manualMark {
            manualHeader
        } else if c.id == Self.meshMeMark {
            meCard.padding(.horizontal, MTLibraryRow.side).padding(.top, 12)   // off the edges as the posts (26.09)
        } else if c.id == Self.meshNearMark {
            MontanaMeshCard(onOpenChat: { ref in onOpenChat(ref) },
                            onOpenRoom: { ui.openChat(Chat(name: meshRoomKey, lastMessage: "", time: "", unread: 0, status: "")) })
        } else if c.id == Self.p2pMark {
            p2pTab.padding(.top, 12)
        } else if let plan = plan(c) {
            planHeader(plan)
        } else if let cfg = server(c) {
            serverCell(cfg)
        }
    }
    /// A tap is the list's own selection (15.26): a server is chosen. A header's row answers nothing to the selection: a tap
    /// on a button inside a hosted cell reaches the list's selection too (the music's rows, 24.09), and a fold by the arrow
    /// answered again by the row would be no fold at all -- the arrow and the title fold, the row's selection stays silent.
    private func tap(_ c: Chat) {
        if let cfg = server(c) { selectServer(cfg) }
    }
    /// A hold is the container's own (16.09): a server's menu -- rename, copy, pin, delete -- in the overlay window, as the
    /// chat's message menu opens. No measure here (the author's word 29.09): the coin and the hour measure.
    private func hold(_ c: Chat) {
        guard let cfg = server(c) else { return }
        let ic = mtServerIcon(cfg.name)
        let items: [(String, String, Bool, () -> Void)] = [
            ("Rename", "pencil", false, { renameText = cfg.name; renameServer = cfg }),
            ("Copy link", "doc.on.doc", false, { copyLink(cfg) }),
            ("Copy JSON", "curlybraces", false, { copyJSON(cfg) }),
            ("Pin", "pin", false, { pinServer(cfg) }),
            ("Delete", "trash", true, { deleteServer(cfg) }),
        ]
        presentMontanaVPNMenu(title: ic.clean, emoji: ic.emoji, items: items)
    }
    /// The container's own swipe on a server (15.26): from the right -- pin it to the head of its section, and delete it. The
    /// swipe from the left carries nothing since 29.09 (the author's word: nothing on the page measures by hand).
    private func swipeLeading(_ c: Chat) -> [SwipeTile] { [] }
    private func swipeTrailing(_ c: Chat) -> [SwipeTile] {
        guard let cfg = server(c) else { return [] }
        return [SwipeTile(icon: "pin.fill", color: SwipeTile.glass) { vpnMark("swipe", "pin row=\(shortId(cfg))"); pinServer(cfg) },
                SwipeTile(icon: "trash.fill", color: SwipeTile.glass) { vpnMark("swipe", "delete row=\(shortId(cfg))"); deleteServer(cfg) }]
    }

    /// The head of the page: on the VPN wall the power button, the live timer, the tunnel's own error and the line the page
    /// speaks with; on the mesh and the P2P walls the wall's own head.
    private var head: some View {
        VStack(spacing: 16) {
            if selected == 0 { vpnHead } else { wallHead }
        }
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
                      : LocalizedStringKey("P2P wall: the nodes this phone reaches, and the switch over them"))
                .font(.footnote).foregroundColor(.secondary).multilineTextAlignment(.center)
                .padding(.horizontal, 28)
        }
        .padding(.top, 16)
    }

    /// The shared chat-list line; its native separator belongs to the collection view.
    private func serverCell(_ cfg: MontanaVPNConfig) -> some View {
        MontanaVPNServerRow(cfg: cfg, selected: cfg.id == tunnel.selectedId, ping: delays.entries[cfg.id])
    }

    // The power button, the live timer, the tunnel's own error and the line a load speaks with.
    @ViewBuilder private var vpnHead: some View {
        VStack(spacing: 16) {
            // THE WALL'S ONE LINE (the author's word 29.09: «a short caption above the button: the VPN wall -- here appear all your
            // subscriptions and your contacts', as a publication on the wall with posts»).
            Text("VPN wall: every subscription of yours and of your contacts appears here")
                .font(.footnote).foregroundColor(.secondary).multilineTextAlignment(.center)
                .padding(.horizontal, 28).padding(.top, 16)
            // 3D convex power button: red = off, amber = connecting, green = connected. Tap = start/stop the tunnel.
            Button { toggleVPN() } label: { MontanaVPNPowerButton(state: vpnPowerState) }
                .buttonStyle(.plain)
                .disabled(vpnServers.isEmpty)
                .padding(.top, 8)

            // Connected -> green live timer hh:mm:ss; off -> nothing (the button itself is red). No on/off text.
            if tunnel.status == .connected, let since = tunnel.connectedAt {
                // The system's own live timer: it is driven by the OS from the connection instant, so it
                // never lags, never skips and is immune to this screen re-rendering. Hand-rolled ticking
                // (a periodic schedule + elapsed arithmetic) had none of those properties.
                Text(timerInterval: since...Date.distantFuture, countsDown: false, showsHours: true)
                    .font(.system(size: 36, weight: .bold, design: .monospaced))
                    .monospacedDigit().foregroundColor(.green)
            }
            // THE VPN OF MONTANA'S NODES FOR TIME COINS (MTVPNPay, the author's words 05.10.2026 22:56-23:2x MSK): the entrance path's
            // door plate in the platform's blue, under the power; it lays the paid rows and raises them by the power's own road.
            payPlate
            if !tunnel.lastError.isEmpty {
                Text(tunnel.lastError).font(.caption).foregroundColor(.red).multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity).padding(.horizontal)
            }
            // THE VPN WALL'S WORD UNDER THE PERMITTED LIST (the author's word 30.09): what the wall's road found and did, in the
            // person's language -- the node it raised from the wall, the ten minutes the person's choice stands, or no live node.
            if let line = road.line {
                Text(line).font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity).padding(.horizontal)
            }
            if !tunnel.backgroundError.isEmpty {
                Text(tunnel.backgroundError).font(.caption).foregroundColor(.red).multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity).padding(.horizontal)
            }

            // The line the page speaks with: what a load is doing, or the word of the last action. The coin's pull loads the plans
            // and measures the list behind the page, the hour does the same by itself, the gauge on a section's header measures that
            // section (back on 29.09 evening by the author's word), and the rows draw the book of delays. The power button is the
            // power and nothing else.

            if let note = vpnNote { Text(note).font(.caption).foregroundColor(.secondary).frame(maxWidth: .infinity, alignment: .leading) }

            if vpnServers.isEmpty && plans.isEmpty {
                Text("Add an exit node with the plus below.").font(.callout).foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, MTLibraryRow.side).padding(.vertical, 12)
            }
        }
    }

    // The header of the hand-added section, the same shape a plan wears.
    private var manualHeader: some View {
        sectionHeader(expanded: vpnListExpanded,
                      title: Text(plans.isEmpty ? LocalizedStringKey("Exit nodes") : LocalizedStringKey("Added by hand")),
                      subtitle: Text("\(manualServers.count) servers"),
                      busy: false,
                      onFold: { foldManual() },
                      onRefresh: nil, onPing: { pingAll(manualServers) }, measuring: measuring(manualServers),
                      menu: { presentMontanaVPNMenu(title: String(localized: "Servers", bundle: MTLanguage.bundle), emoji: nil, items: [
                          (manualPinnedAt == nil ? "Pin" : "Unpin", manualPinnedAt == nil ? "pin" : "pin.slash", false, { toggleManualPin() }),
                          ("Sort by ping", "arrow.up.arrow.down", false, { sortByPing() }),
                      ]) })
            .padding(.horizontal, MTLibraryRow.side).padding(.top, 12)   // off the edges as the posts; a breath above the section (26.09)
    }
    /// The hand-added section's fold: the rows move at once, the fold outlives the page (the author's word 24.09).
    private func foldManual() {
        vpnMark("fold", "manual to=\(vpnListExpanded ? "folded" : "open")")
        withAnimation(.easeInOut(duration: 0.2)) { vpnListExpanded.toggle() }
        MontanaVPNPlans.setManualFolded(!vpnListExpanded)
    }

    // The header every section wears (the reference clients draw it so): fold, name, a line under it, then
    // refresh (a plan only), the gauge that measures the section, and the menu. The gauge left in the afternoon of 29.09 and
    // came back that evening by the author's word («bring the ping button back for every subscription; the hand-added
    // section wears the same panel and the same button»). The arrow and the title fold the section; the row's own selection
    // does nothing on a header (see tap). While the section's rows are in flight the gauge spins (one owner: the ping line).
    @ViewBuilder private func sectionHeader(expanded: Bool, title: Text, subtitle: Text, busy: Bool,
                                            onFold: @escaping () -> Void, onRefresh: (() -> Void)?,
                                            onPing: (() -> Void)?, measuring: Bool = false,
                                            menu: @escaping () -> Void) -> some View {
        HStack(spacing: 4) {
            Button { onFold() } label: {
                Image(systemName: expanded ? "chevron.down" : "chevron.right")
                    .font(.subheadline.weight(.bold)).foregroundColor(.secondary)
                    .frame(width: montanaTouchTarget, height: montanaTouchTarget).contentShape(Rectangle())
            }.buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 2) {
                title.font(.system(size: 19, weight: .bold)).foregroundColor(.white).lineLimit(1)
                subtitle.font(.caption).foregroundColor(.secondary).lineLimit(1)
            }
            .contentShape(Rectangle()).onTapGesture(perform: onFold)
            Spacer(minLength: 4)
            if let onRefresh {
                Button { onRefresh() } label: {
                    Group { if busy { ProgressView() } else { Image(systemName: "arrow.triangle.2.circlepath").font(.title3).foregroundColor(.secondary) } }
                        .frame(width: montanaTouchTarget, height: montanaTouchTarget).contentShape(Rectangle())
                }.buttonStyle(.plain).disabled(busy)
            }
            if let onPing {
                Button { onPing() } label: {
                    Group { if measuring { ProgressView() } else { Image(systemName: "gauge.with.dots.needle.bottom.50percent").font(.title3).foregroundColor(.secondary) } }
                        .frame(width: montanaTouchTarget, height: montanaTouchTarget).contentShape(Rectangle())
                }.buttonStyle(.plain).disabled(measuring)
            }
            Button { menu() } label: {
                Image(systemName: "ellipsis").font(.title3).foregroundColor(.secondary)
                    .frame(width: montanaTouchTarget, height: montanaTouchTarget).contentShape(Rectangle())
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, 6).padding(.vertical, 6)
    }

    // A plan's header: its name and word above, the counters the panel states below -- one row of the page, folded or
    // unfolded by its arrow and by a tap on the row.
    @ViewBuilder private func planHeader(_ plan: MontanaVPNPlan) -> some View {
        let rows = servers(of: plan)
        let busy = loadingPlan == plan.url || loadingPlan == "*"
        let expanded = plan.folded != true
        let wall = MTVPNWall.isWallKey(plan.url)   // a correspondent's wall: their name above, their servers below, no panel words (29.09)
        VStack(spacing: 0) {
            sectionHeader(expanded: expanded,
                          // USER-DATA: the plan's own title (or its host), never interface text.
                          title: Text(verbatim: plan.shownTitle),
                          // USER-DATA: the moment of the last load that succeeded; the freshener loads a plan again by its
                          // own interval and when the page opens on an old one (29.09).
                          subtitle: plan.updatedAt > 0
                              ? Text(verbatim: mtStamp(plan.updatedAt))
                              : (plan.lastError.map { Text("subscription failed: \($0)") } ?? Text("loading subscription…")),
                          busy: busy,
                          onFold: { fold(plan) },
                          onRefresh: { refreshPlan(plan) }, onPing: { pingAll(rows) }, measuring: measuring(rows),
                          menu: { presentMontanaVPNMenu(title: plan.shownTitle, emoji: nil, items: [
                              (plan.pinnedAt == nil ? "Pin subscription" : "Unpin subscription",
                               plan.pinnedAt == nil ? "pin" : "pin.slash", false, { togglePin(plan) }),
                              ("Update", "arrow.triangle.2.circlepath", false, { refreshPlan(plan) }),
                              ("Copy link", "doc.on.doc", false, { UIPasteboard.general.string = plan.url; vpnNote = "link copied" }),
                              ("Delete subscription", "trash", true, { vpnMark("plan", "delete \(MontanaLog.label(plan.url)) rows=\(rows.count)")
                                                                       MontanaVPNStore.removeSubscription(plan.url); reloadVPN()
                                                                       MTVPNWall.shared.schedulePush() }),   // the wall no longer names it (29.09)
                          ].filter { !wall || ($0.0 != "Copy link" && $0.0 != "Delete subscription") }) })
            // Folded, the plan is its one line (the author's word 24.09): the arrow, the name and its word, the
            // update, the gauge and the menu. What the panel counts, and a failure under it, wait for the unfold.
            if expanded, !wall, plan.updatedAt > 0 {
                HStack(spacing: 10) {
                    // USER-DATA: the bytes the panel counted; "∞" is the panel's own sign of no limit.
                    Text(verbatim: mtBytes((plan.download ?? 0) + (plan.upload ?? 0)) + " / " + ((plan.total ?? 0) > 0 ? mtBytes(plan.total ?? 0) : "∞"))
                        .font(.caption.weight(.semibold)).foregroundColor(.white)
                        .padding(.horizontal, 14).padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.35), lineWidth: 1))
                    if let e = plan.expire, e > 0 { Text("expires \(mtDay(e))").font(.caption).foregroundColor(.white.opacity(0.9)) }
                    Spacer()
                    Button { UIPasteboard.general.string = plan.url; vpnNote = "link copied" } label: {
                        Image(systemName: "link").font(.body).foregroundColor(.secondary)
                            .frame(width: montanaTouchTarget, height: montanaTouchTarget).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
                .padding(.leading, 12).padding(.trailing, 6)
            }
            // The rows the engine cannot speak, counted under the header (29.09): the plan came in whole and says what of it stands grey.
            if expanded, let n = plan.unsupported, 0 < n {
                Text("\(n) not supported: \(plan.unsupportedKinds ?? "")").font(.caption).foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).padding(.vertical, 4)
            }
            // Once: a plan that never loaded says its failure in the header's own line above.
            if expanded, plan.updatedAt > 0, let err = plan.lastError {
                Text("subscription failed: \(err)").font(.caption).foregroundColor(.red)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).padding(.vertical, 6)
            }
        }
        .padding(.horizontal, MTLibraryRow.side).padding(.top, 12)
    }

    /// The fold outlives the page (the author's word 24.09: «if I folded a plan's servers with the arrow, it must
    /// remember»): the section moves at once, and the sealed plan keeps it on the next turn of the loop.
    private func fold(_ plan: MontanaVPNPlan) {
        let expanded = plan.folded != true
        vpnMark("fold", "plan=\(MontanaLog.label(plan.url)) to=\(expanded ? "folded" : "open") rows=\(servers(of: plan).count)")
        withAnimation(.easeInOut(duration: 0.2)) { togglePlan(plan.url) }
    }
    private func togglePlan(_ url: String) {
        guard let i = plans.firstIndex(where: { $0.url == url }) else { return }
        let folded = plans[i].folded != true
        plans[i].folded = folded ? true : nil
        DispatchQueue.main.async { MontanaVPNPlans.setFolded(url, folded) }
    }
    /// A pinned plan stands above the unpinned, and the newest pin above every earlier one (the author's word 24.09).
    private func togglePin(_ plan: MontanaVPNPlan) {
        let pin = plan.pinnedAt == nil
        vpnMark("plan", "\(pin ? "pin" : "unpin") rows=\(servers(of: plan).count)")
        MontanaVPNPlans.setPinned(plan.url, pin)
        withAnimation(.easeInOut(duration: 0.2)) { reloadVPN() }
    }
    /// The hand-added section is pinned from its menu as a plan is (the author's word 24.09), and stands among the
    /// pins by its moment: the newest pin highest, the rule the plans keep.
    private func toggleManualPin() {
        let pin = manualPinnedAt == nil
        vpnMark("plan", "\(pin ? "pin" : "unpin") manual rows=\(manualServers.count)")
        MontanaVPNPlans.setManualPinned(pin)
        withAnimation(.easeInOut(duration: 0.2)) { reloadVPN() }
    }
    private func mtStamp(_ t: Double) -> String {
        let f = DateFormatter(); f.locale = MTLanguage.locale; f.dateStyle = .short; f.timeStyle = .short
        return f.string(from: Date(timeIntervalSince1970: t))
    }
    private func mtDay(_ t: Double) -> String {
        let f = DateFormatter(); f.locale = MTLanguage.locale; f.dateStyle = .medium; f.timeStyle = .none
        return f.string(from: Date(timeIntervalSince1970: t))
    }
    private func mtBytes(_ n: Int64) -> String { n.formatted(.byteCount(style: .binary).locale(MTLanguage.locale)) }
    private func refreshPlan(_ plan: MontanaVPNPlan) {
        if let conv = plan.wallOf, MTVPNWall.isWallKey(plan.url) {   // a correspondent's wall: asked of them, never fetched (29.09)
            vpnMark("update", "wall ask=\(String(conv.prefix(10)))"); MTVPNWall.shared.ask(conv); return
        }
        guard let url = URL(string: plan.url), loadingPlan == nil else { return }
        let t0 = Date()
        loadingPlan = plan.url
        vpnMark("update", "plan=\(MontanaLog.label(plan.url)) was=\(servers(of: plan).count)")
        Task {
            do {
                _ = try await MontanaVPNStore.addFromSubscription(url) { k in vpnNote = "loading subscription… attempt \(k) of \(MontanaVPNSubscription.attempts)" }
                vpnNote = nil
            // The failure is said ONCE, by the plan's own line under its header (the store writes it there);
            // the page's line only counted the attempts while they ran.
            } catch let e as MontanaVPNSubscription.FetchError { vpnNote = nil; vpnMark("update", "plan=\(MontanaLog.label(plan.url)) failed \(e.label)") }
            catch { vpnNote = "subscription failed"; vpnMark("update", "plan=\(MontanaLog.label(plan.url)) failed other") }
            loadingPlan = nil; reloadVPN()
            vpnMark("update", "plan=\(MontanaLog.label(plan.url)) now=\(servers(of: plan).count) ms=\(Int(Date().timeIntervalSince(t0) * 1000))")
        }
    }
    private var vpnPowerState: MontanaVPNPowerButton.S {
        switch tunnel.status {
        case .connected: return .on
        case .connecting, .reasserting: return .connecting
        default: return (vpnBusy || tunnel.requested) ? .connecting : .off
        }
    }
    private var selectedServer: MontanaVPNConfig? { book.byId[tunnel.selectedId] }
    private var manualServers: [MontanaVPNConfig] { book.manual }
    private func servers(of plan: MontanaVPNPlan) -> [MontanaVPNConfig] { book.byPlan[plan.url] ?? [] }
    private func idx(_ id: String) -> Int? { manualServers.firstIndex { $0.id == id } }
    /// A row in the diary is named by its identity and its address family, never by the plan's secret.
    private func shortId(_ c: MontanaVPNConfig) -> String { String(c.id.prefix(8)) }

    /// THE GAUGE ON A SECTION'S HEADER MEASURES THAT SECTION (the author's word 29.09, evening: «bring the ping button back for
    /// every subscription; the hand-added section wears the same panel and the same button»): six at a time by the one line
    /// (MontanaVPNPingLine), each answer into the book of delays as it comes. The power button stays the power alone.
    private func pingAll(_ list: [MontanaVPNConfig]) {
        vpnMark("ping", "section rows=\(list.count)")
        MontanaVPNPingLine.shared.ask(list)
    }
    /// Whether any row of the section is being measured now -- the header's gauge spins on the line's own word.
    private func measuring(_ list: [MontanaVPNConfig]) -> Bool {
        let flying = pingLine.inFlight
        return !flying.isEmpty && list.contains { flying.contains($0.id) }
    }

    /// Pinned means first IN ITS OWN SECTION: a hand-added server goes to the head of the hand-added
    /// list, a plan's server to the head of that plan. Nothing crosses a section boundary -- the sections
    /// are what the screen shows, and an order ignoring them would move a row out of sight.
    private func pinServer(_ server: MontanaVPNConfig) {
        let key = server.subscription
        var group = vpnServers.filter { $0.subscription == key }
        guard let i = group.firstIndex(where: { $0.id == server.id }), i > 0 else { return }
        group.insert(group.remove(at: i), at: 0)
        let head = vpnServers.firstIndex(where: { $0.subscription == key }) ?? vpnServers.count
        var rest = vpnServers.filter { $0.subscription != key }
        rest.insert(contentsOf: group, at: min(head, rest.count))
        withAnimation(.easeInOut(duration: 0.2)) { vpnServers = rest }
        MontanaVPNStore.save(vpnServers)
        vpnMark("pin", "row=\(shortId(server)) section=\(key == nil ? "manual" : "plan")")
    }
    private func sortByPing() {
        withAnimation(.easeInOut(duration: 0.2)) {
            vpnServers.sort { (delays.entries[$0.id]?.ms ?? Int.max) < (delays.entries[$1.id]?.ms ?? Int.max) }
        }
        MontanaVPNStore.save(vpnServers)
    }
    /// Everything this page does lands in the device's diary under one word, so a question about it is
    /// answered by reading rather than by guessing: what was pressed, what answered, and how long it
    /// took. Names of plans and addresses stay out -- an identity prefix is enough to follow a row.
    private func vpnMark(_ event: String, _ detail: String) {
        MontanaP2PTrace.mark("vpn_ui", "\(event) \(detail)")
    }

    private func reloadVPN() {
        let t0 = Date()
        vpnServers = MontanaVPNStore.load()
        plans = MontanaVPNPlans.ordered(wallRank: MTVPNWall.chatRank())   // the walls in the chats' order, the freshest first (29.09)
        manualPinnedAt = MontanaVPNPlans.manualPinnedAt
        vpnMark("list", "plans=\(plans.count) manual=\(manualServers.count) all=\(vpnServers.count) ms=\(Int(Date().timeIntervalSince(t0) * 1000))")
        // A vanished row: the installed configuration names the chosen one first (adoptInstalledRow), the list's first only then.
        if book.byId[tunnel.selectedId] == nil { tunnel.adoptInstalledRow() }
        if book.byId[tunnel.selectedId] == nil { MontanaVPNSelection.adopt(vpnServers.first?.id ?? "") }
    }
    // EVERY ROAD IN IS ONE ROAD (29.09): the clipboard, the camera, a file, the hand -- a text arrives here and is read by its
    // shape (MontanaVPNIntake): a plan's link is fetched and every server of the plan lands at once; anything else -- a share
    // link or a list of them, a base64 blob, an engine JSON, a sing-box or Clash body, a WireGuard interface, a Hysteria 2
    // config, a profile the engine cannot speak -- is read in place, and its rows join the hand-added section.
    private func addVPNText(_ raw: String, from road: String, name: String = "") {
        switch MontanaVPNIntake.read(raw, name: name) {
        case .subscription(let url):
            vpnMark("add", "from=\(road) kind=subscription chars=\(raw.count)")
            guard loadingPlan == nil else { vpnMark("add", "busy -- a load is already running"); return }
            loadingPlan = url.absoluteString
            vpnNote = "loading subscription…"
            Task {
                do {
                    _ = try await MontanaVPNStore.addFromSubscription(url) { k in vpnNote = "loading subscription… attempt \(k) of \(MontanaVPNSubscription.attempts)" }
                    // Done is not a message: the plan's header now carries the count and the moment, and
                    // a line repeating it under the button would outlive the act it describes.
                    vpnNote = nil
                // A link that never loaded stands as a plan whose header names the failure: said there, once.
                } catch let e as MontanaVPNSubscription.FetchError { vpnNote = nil; vpnMark("add", "failed \(e.label)") }
                catch { vpnNote = "subscription failed"; vpnMark("add", "failed other") }
                loadingPlan = nil; reloadVPN()
                MTVPNWall.shared.schedulePush()   // a pasted plan is a line of the person's wall (29.09)
            }
        case .servers(let read):
            let unspoken = MontanaVPNParse.Report(servers: read.servers).unsupportedWord
            vpnMark("add", "from=\(road) form=\(read.form) servers=\(read.servers.count) unsupported=\(unspoken.isEmpty ? "-" : unspoken) dropped=\(read.dropped) chars=\(raw.count)")
            addVPNServers(read.servers, from: road, form: read.form)
        }
    }
    /// The rows that came in by hand join the list (MontanaVPNStore.add, the one owner); the page's line says once what did not:
    /// a text with no server in it, or rows the list already held.
    private func addVPNServers(_ servers: [MontanaVPNConfig], from road: String, form: String) {
        guard !servers.isEmpty else {
            vpnNote = form == "links" || form == "base64" ? "invalid link" : "no server found"
            return
        }
        let joined = MontanaVPNStore.add(servers)
        reloadVPN()
        vpnMark("add", "from=\(road) joined=\(joined) of=\(servers.count)")
        vpnNote = joined == 0 ? "already in the list" : nil
        if 0 < joined { MTVPNWall.shared.schedulePush() }   // a hand-added server is a line of the person's wall (29.09)
    }
    /// THE FILE ROAD (the author's word 29.09: «a profile as a .config file, or any other proper VPN file»): the platform's own
    /// file picker, any file -- the shape decides, never the extension (MontanaVPNSubscription.body). The picker's URL is opened
    /// under its security scope for the read alone; a file over a megabyte is no profile; the file's name names the server
    /// when its form carries no name.
    private func importVPNFiles(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result else { vpnMark("add", "from=file picker refused"); return }
        Task {
            let read = await MontanaVPNIntake.readFiles(urls)   // the disk is read off the main thread (the layout ring, rule 6)
            for file in read.texts { addVPNText(file.text, from: "file", name: file.name) }
            if 0 < read.unreadable {
                vpnNote = "the file could not be read"
                vpnMark("add", "from=file unreadable=\(read.unreadable) of=\(urls.count)")
            }
        }
    }
    /// COPY JSON (the author's example menu 29.09): the row's whole engine config, in the form this page reads back
    /// (MontanaXrayConfig.shareJSON) -- the chosen server from the plus, any server from its hold.
    private func copyJSON(_ server: MontanaVPNConfig?) {
        guard let server, let text = MontanaXrayConfig.shareJSON(server) else { vpnNote = "not supported by the engine"; return }
        UIPasteboard.general.string = text
        vpnNote = "JSON copied"
        vpnMark("copy", "json row=\(shortId(server)) chars=\(text.count)")
    }
    private func refreshSubscriptions() {
        guard loadingPlan == nil else { return }
        loadingPlan = "*"
        vpnNote = "loading subscription…"
        Task {
            _ = await MontanaVPNStore.refreshSubscriptions { k in vpnNote = "loading subscription… attempt \(k) of \(MontanaVPNSubscription.attempts)" }
            vpnNote = nil   // each plan says its own failure under its own header, once
            loadingPlan = nil; reloadVPN()
        }
    }
    private func pasteVPN() {
        guard let s = UIPasteboard.general.string, !s.isEmpty else { vpnNote = "no server found"; return }
        addVPNText(s, from: "paste")
    }
    /// The plate of the VPN for coins (MTVPNPay): while the tunnel rides Montana's paid rows it says the price and stops it by the
    /// power's road; else it pays, lays the rows and raises them by the same road.
    @ViewBuilder private var payPlate: some View {
        let level = MTVPNPay.perSecond
        let rides = MTVPNPay.rides(tunnel)
        VStack(spacing: 6) {
            Button { if rides { toggleVPN() } else { payAndConnect() } } label: {
                rides ? Text("Paying · \(level) a second") : Text("Pay with coins · \(level) a second")
            }
            .buttonStyle(MTLoginDoorStyle(tint: MontanaOctagon.platformBlue))
            .disabled(pay.busy || vpnBusy)
            .padding(.horizontal, 28)
            if let word = pay.word {
                Text(word).font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center).padding(.horizontal, 28)
            }
        }
    }
    private func payAndConnect() {
        Task {
            guard await pay.prepare() else { return }
            reloadVPN()
            if !tunnel.isOn { toggleVPN() }
        }
    }
    private func toggleVPN() {
        guard let c = selectedServer else { vpnNote = "invalid link"; vpnMark("power", "no server selected"); return }
        MontanaVPNSelection.noteHand()   // the person's hand on the VPN: nothing automatic raises another row within ten minutes
        if tunnel.isOn { vpnMark("power", "stop row=\(shortId(c))"); Task { await tunnel.stop() }; return }
        let t0 = Date()
        vpnBusy = true; vpnNote = nil
        vpnMark("power", "start row=\(shortId(c)) net=\(c.network) sec=\(c.security)")
        Task {
            do {
                try await tunnel.start(c, byHand: true)   // the one road that may give birth to the profile (30.09)
                vpnMark("power", "asked ms=\(Int(Date().timeIntervalSince(t0) * 1000))")
            } catch {
                vpnNote = LocalizedStringKey(MontanaVPNPing.startErr(error))
                vpnMark("power", "refused \((error as NSError).domain)#\((error as NSError).code) ms=\(Int(Date().timeIntervalSince(t0) * 1000))")
            }
            vpnBusy = false
        }
    }
    private func selectServer(_ server: MontanaVPNConfig) {
        guard server.proto != .unsupported else {   // the grey row says what it is; a tap explains it, nothing is installed (29.09)
            vpnNote = "not supported by the engine"
            vpnMark("select", "refused row=\(shortId(server)) scheme=\(server.scheme ?? "?")")
            return
        }
        let t0 = Date()
        let restart = tunnel.isOn
        if restart { vpnBusy = true }
        Task {
            // One writer of the choice (MontanaVPNSelection): the person's tap and the calls' pick alike.
            await MontanaVPNSelection.select(server, why: "hand")
            guard restart else { return }
            vpnBusy = false
            vpnMark("select", "restarted row=\(shortId(server)) ms=\(Int(Date().timeIntervalSince(t0) * 1000))")
        }
    }
    private func copyLink(_ server: MontanaVPNConfig) {
        UIPasteboard.general.string = MontanaVPNParse.serialize(server); vpnNote = "link copied"
    }
    /// A row leaves the list. One of a plan stays gone until that plan is asked again -- the plan's list
    /// is the plan's word, and this client does not argue with it behind the person's back.
    private func deleteServer(_ server: MontanaVPNConfig) {
        guard let i = vpnServers.firstIndex(where: { $0.id == server.id }) else { return }
        vpnMark("delete", "row=\(shortId(server)) section=\(server.subscription == nil ? "manual" : "plan")")
        MontanaVPNStore.remove(at: i); reloadVPN()
        if server.subscription == nil { MTVPNWall.shared.schedulePush() }   // the wall no longer names it (29.09)
    }
    private func doRename() {
        if let server = renameServer, let i = idx(server.id), !renameText.trimmingCharacters(in: .whitespaces).isEmpty {
            MontanaVPNStore.rename(at: i, to: renameText); reloadVPN()
            MTVPNWall.shared.schedulePush()   // the wall carries the new name (29.09)
        }
        renameServer = nil; renameText = ""
    }

    // SSOT canonical transport icon -- same source as the chats header and bubbles; white by default, the platform's blue
    // on the chosen tab (the author's word 25.09).
    @ViewBuilder private func symbol(_ idx: Int, chosen: Bool) -> some View {
        // VPN (Mode B, not a delivery transport): the globe-on-a-stand asset. Mesh: the antenna -- one icon for the network itself.
        let tint = chosen ? MontanaOctagon.platformBlue : Color.white
        if idx == 0 {
            MontanaVPNGlyph(color: tint, size: 26)
        } else if idx == 2 {
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




// SSOT VPN glyph ([I-10]/[C-1]): the author-specified globe-on-a-stand asset (MontanaVPNGlobe, template),
// tinted like the transport icons. Single place any code references the asset name.
struct MontanaVPNGlyph: View {
    var color: Color
    var size: CGFloat = 26
    var body: some View {
        Image("MontanaVPNGlobe").renderingMode(.template).resizable().scaledToFit()
            .frame(width: size, height: size).foregroundColor(color)
    }
}


// 3D convex power button for the VPN tab (Mode B): red = off, amber = connecting, green = connected.
// Glossy raised look (radial highlight + bottom shade + rim), power glyph centred; state animates.
/// THE BUTTON IS THE POWER AND NOTHING ELSE (the author's word 29.09, after T1 at 15:28 MSK: the gauge and the count that stood in
/// its middle since 28.09 read as another control, and a tap on them switched the tunnel off 1.7 s after it came up). No ring, no
/// count, no gauge: on and off. The rows say what is being measured.
struct MontanaVPNPowerButton: View {
    enum S { case off, connecting, on }
    let state: S
    private var c: Color {
        switch state {
        case .off:        return Color(red: 0.91, green: 0.23, blue: 0.20)
        case .connecting: return Color(red: 0.96, green: 0.62, blue: 0.15)
        case .on:         return Color(red: 0.19, green: 0.80, blue: 0.36)
        }
    }
    var body: some View {
        ZStack {
            Circle().fill(c.opacity(0.22)).frame(width: 184, height: 184).blur(radius: 16)          // ambient glow
            Circle().fill(c).frame(width: 150, height: 150)
                .overlay(Circle().fill(RadialGradient(colors: [.white.opacity(0.7), .clear],
                    center: UnitPoint(x: 0.34, y: 0.24), startRadius: 2, endRadius: 82)))            // convex top highlight
                .overlay(Circle().fill(RadialGradient(colors: [.clear, .black.opacity(0.38)],
                    center: UnitPoint(x: 0.7, y: 0.85), startRadius: 24, endRadius: 96)))            // bottom shade
                .overlay(Circle().stroke(LinearGradient(colors: [.white.opacity(0.6), .clear, .black.opacity(0.4)],
                    startPoint: .top, endPoint: .bottom), lineWidth: 2))                              // rim
                .clipShape(Circle())
                .shadow(color: c.opacity(0.65), radius: 22, x: 0, y: 8)
                .shadow(color: .black.opacity(0.6), radius: 9, x: 0, y: 10)
            if state == .connecting {
                ProgressView().scaleEffect(1.9).tint(.white)
            } else {
                Image(systemName: "power").font(.system(size: 60, weight: .heavy)).foregroundColor(.white)
                    .shadow(color: .black.opacity(0.45), radius: 3, x: 0, y: 2)
            }
        }
        .frame(width: 190, height: 190)
        .animation(.easeInOut(duration: 0.22), value: state)
    }
}

/// THE PING LINE, SIX AT A TIME (the author's word 29.09: «ping six servers at once», which supersedes «in turn» of 28.09 now
/// that a batch rides ONE engine instance -- the four engines of 22.09 that moved each other's numbers are gone, and under a
/// standing tunnel the provider measures the batch through one instance too, PacketTunnelProvider «probes:»). Only the person's
/// finger on a section's gauge asks it (pingAll; the author's word 30.09: «a ping only at a press of the hand»); the
/// line walks the list in batches of MontanaVPNDelay.width behind the page, every answer lands in the book of delays as it
/// comes, and the rows in flight wear a spinner beside their last number. A row the engine cannot speak is not asked. The
/// deadline of a batch lives in the engine (8 s), so nothing of a batch outlives the line (the critic's P-2).
@MainActor final class MontanaVPNPingLine: ObservableObject {
    static let shared = MontanaVPNPingLine()
    @Published private(set) var done = 0
    @Published private(set) var total = 0
    /// The servers being measured now.
    @Published private(set) var inFlight: Set<String> = []
    private var waiting: [(id: String, cfg: MontanaVPNConfig)] = []
    private var queued: Set<String> = []
    private var running = false
    private var began = Date()
    private var answered: [Int] = []
    private var failed = 0

    /// Asks every server of `list` not already waiting.  Measurement reports a condition; it never
    /// chooses a server or changes the tunnel.
    func ask(_ list: [MontanaVPNConfig]) {
        var fresh = 0
        for c in list where c.proto != .unsupported {
            guard queued.insert(c.id).inserted else { continue }
            waiting.append((c.id, c))
            fresh += 1
        }
        guard fresh != 0 else { return }
        total += fresh
        MontanaP2PTrace.mark("vpn_ui", "ping line asked=\(fresh) waiting=\(waiting.count) of=\(total)")
        guard !running else { return }
        running = true
        began = Date(); answered = []; failed = 0
        Task { await self.walk() }
    }

    private func walk() async {
        let book = MontanaVPNDelayBook.shared
        while !waiting.isEmpty {
            let batch = Array(waiting.prefix(MontanaVPNDelay.width))
            waiting.removeFirst(batch.count)
            let t0 = Date()
            inFlight = Set(batch.map { $0.id })
            var results = await MontanaVPNDelay.measureMany(batch.map { $0.cfg })
            // «busy» is the tunnel's word about itself (its engine line recovering, its memory short), never the servers'
            // verdict: the batch is asked once more after a breath, and a second «busy» stands as what it is.
            if results.contains(where: { $0.err == "busy" }) {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                results = await MontanaVPNDelay.measureMany(batch.map { $0.cfg })
            }
            let measurementFault = results.count == batch.count && results.allSatisfy {
                $0.ms == nil && ["busy", "unreachable", "timeout", "connection error"].contains($0.err ?? "")
            }
            if measurementFault {
                MontanaP2PTrace.mark("vpn_ui", "ping batch indeterminate n=\(batch.count); kept last confirmed rows")
            }
            for (i, item) in batch.enumerated() {
                let r: (ms: Int?, err: String?) = i < results.count ? results[i] : (nil, "connection error")
                queued.remove(item.id)
                done += 1
                if !measurementFault {
                    if let ms = r.ms { answered.append(ms) } else { failed += 1 }
                    book.record(item.id, r)
                }
                MontanaP2PTrace.mark("vpn_ui", "ping row=\(item.id.prefix(8)) net=\(item.cfg.network) ms=\(r.ms.map(String.init) ?? "-") err=\(r.err ?? "-") step=\(done)/\(total)")
            }
            book.persist()
            inFlight = []
            MontanaP2PTrace.mark("vpn_ui", "ping batch n=\(batch.count) took=\(Int(Date().timeIntervalSince(t0) * 1000))")
        }
        MontanaP2PTrace.mark("vpn_ui", "ping all done n=\(done) ok=\(answered.count) fail=\(failed) best=\(answered.min() ?? 0) worst=\(answered.max() ?? 0) took=\(Int(Date().timeIntervalSince(began) * 1000))")
        running = false
        done = 0; total = 0
        MTVPNWall.shared.schedulePush()
    }
}

func mtPingColor(_ ms: Int) -> Color { ms < 120 ? .green : (ms < 250 ? .orange : .red) }

// A server uses the chats' shared line: icon, name and protocol, UDP and ping; a checkmark names the selection. THE TAP,
// THE HOLD AND THE SWIPE ARE THE LIST'S OWN (NetworkTabView, 15.26 and 16.09): the row draws, and answers nothing itself.
struct MontanaVPNServerRow: View {
    let cfg: MontanaVPNConfig
    let selected: Bool
    let ping: MontanaVPNDelayBook.Entry?   // what this server last answered, and when (the book of delays, 29.09)
    @ObservedObject private var line = MontanaVPNPingLine.shared   // the servers measured now wear a spinner (29.09)

    var body: some View {
        content.modifier(MTLibraryLine())
    }

    private var content: some View {
        let ic = mtServerIcon(cfg.name)
        return HStack(spacing: MTLibraryRow.gap) {
            RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.10)).frame(width: MTLibraryRow.face, height: MTLibraryRow.face)
                .overlay(
                    Group {
                        if let e = ic.emoji { Text(e).font(.system(size: 26)) }
                        else { MontanaVPNGlyph(color: selected ? MontanaOctagon.platformBlue : Color.white.opacity(0.85), size: 22) }
                    }
                )
            VStack(alignment: .leading, spacing: 4) {
                Text(ic.clean).font(.system(size: 17, weight: .semibold)).foregroundColor(cfg.proto == .unsupported ? .gray : .white).lineLimit(1)
                if cfg.proto == .unsupported {
                    // USER-DATA: the scheme the link came with; the word beside it comes from the catalogue (29.09).
                    (Text(verbatim: (cfg.scheme ?? "?").uppercased() + " · ") + Text("not supported by the engine"))
                        .font(.system(size: 16)).foregroundColor(.gray).lineLimit(1)
                } else {
                    // USER-DATA: the protocol, the transport and the wrapper as the link names them; JSON marks a row a plan served as
                    // a whole engine config (29.09), carried to the engine as it is.
                    Text(verbatim: [cfg.proto.rawValue.uppercased(), cfg.network, cfg.security == "none" ? nil : cfg.security, cfg.engineOutbound == nil ? nil : "JSON"]
                            .compactMap { $0 }.joined(separator: " · "))
                        .font(.system(size: 16)).foregroundColor(.gray).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if selected {
                Image(systemName: "checkmark").font(.system(size: 16, weight: .semibold))
                    .foregroundColor(MontanaOctagon.platformBlue)
            }
            // The last number stands always -- dimmed once it is older than half an hour -- and the spinner rides beside it
            // while a new measurement flies: a row is never empty while the line walks the list (29.09, the critic's P-5).
            if let p = ping {
                if let ms = p.ms {
                    Circle().fill(mtPingColor(ms)).frame(width: 7, height: 7)
                    // USER-DATA: a number of milliseconds; the word "ms" beside it comes from the catalogue.
                    (Text(verbatim: "\(ms) ") + Text("ms")).font(.subheadline).foregroundColor(.secondary)
                        .opacity(p.age < MontanaVPNDelayBook.stale ? 1 : 0.45)
                } else {
                    Circle().fill(Color.red).frame(width: 7, height: 7)
                }
            }
            if line.inFlight.contains(cfg.id) {
                ProgressView().scaleEffect(0.8)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// Extract a leading/first emoji (flag or otherwise) from a server name: use it as the icon and show
// the name without it (the flag is the chip and the title stays clean).
func mtServerIcon(_ name: String) -> (emoji: String?, clean: String) {
    let t = name.trimmingCharacters(in: .whitespaces)
    if let ch = t.first(where: { $0.mtIsEmoji }) {
        var clean = t
        if let r = clean.range(of: String(ch)) { clean.removeSubrange(r) }
        while clean.contains("  ") { clean = clean.replacingOccurrences(of: "  ", with: " ") }
        clean = clean.trimmingCharacters(in: .whitespaces)
        return (String(ch), clean.isEmpty ? t : clean)
    }
    return (nil, t)
}

extension Character {
    var mtIsEmoji: Bool {
        if unicodeScalars.count > 1 { return unicodeScalars.contains { $0.properties.isEmoji } }
        guard let s = unicodeScalars.first else { return false }
        return s.properties.isEmoji && s.value > 0x238C
    }
}


// Server/list context menu shown in MontanaOverlayWindow — the SAME window, materials and spring as
// the chat message menu (MessageContextOverlay), so it opens instantly and reads 1:1 with the chat.
struct MontanaVPNMenuOverlay: View {
    let title: String
    let emoji: String?
    let items: [(title: String, icon: String, destructive: Bool, action: () -> Void)]
    var onClose: () -> Void
    @State private var shown = false

    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial).ignoresSafeArea().onTapGesture { onClose() }
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    if let e = emoji { Text(e).font(.system(size: 24)) }
                    else { MontanaVPNGlyph(color: .green, size: 22) }
                    // USER-DATA: the title arrives ALREADY resolved -- either as a catalogue string
                    // (`String(localized: "Servers")`) or as a server name. It is never a key in any
                    // call, so here a value is shown, not a key.
                    Text(verbatim: title).font(.system(size: 17, weight: .bold)).foregroundColor(.white).lineLimit(1)
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.12), lineWidth: 1))

                VStack(spacing: 0) {
                    ForEach(items.indices, id: \.self) { i in
                        if i > 0 { Divider().overlay(Color.gray.opacity(0.3)) }
                        Button(action: items[i].action) {
                            HStack {
                                Text(LocalizedStringKey(items[i].title)).foregroundColor(items[i].destructive ? .red : .white)
                                Spacer()
                                Image(systemName: items[i].icon).foregroundColor(items[i].destructive ? .red : .white.opacity(0.8))
                            }
                            .font(.system(size: 16)).padding(.horizontal, 14).frame(minHeight: montanaTouchTarget)
                            .contentShape(Rectangle())
                        }
                    }
                }
                .frame(width: 260)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.1), lineWidth: 1))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .scaleEffect(shown ? 1 : 0.94, anchor: .leading)
            .opacity(shown ? 1 : 0)
        }
        .onAppear { withAnimation(.spring(response: 0.32, dampingFraction: 0.68)) { shown = true } }
    }
}

func presentMontanaVPNMenu(title: String, emoji: String?, items: [(String, String, Bool, () -> Void)]) {
    let close = { MontanaOverlayWindow.shared.hide() }
    let wrapped = items.map { it in
        (title: it.0, icon: it.1, destructive: it.2,
         action: { close(); DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { it.3() } })
    }
    MontanaOverlayWindow.shared.show {
        MontanaVPNMenuOverlay(title: title, emoji: emoji, items: wrapped, onClose: close)
    }
}

/// THE FORM OF A SERVER BY HAND (the author's example menu 29.09: «Manual entry»): the platform's own form -- a section per
/// question, a picker for the protocol, the transport and the wrapper, a field for every word the engine honours of that
/// protocol (the words the link parser reads, MontanaVPNParse) -- under the bar's cross and checkmark, as every sheet of the
/// app. The checkmark stands only while the record can be dialled (sealed): a machine, a port, the secret its protocol needs.
struct MontanaVPNManualEntry: View {
    var onSave: (MontanaVPNConfig) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var c = MontanaVPNConfig.empty(.vless)
    @State private var portText = "443"
    @State private var mtuText = ""
    static let protocols: [MontanaVPNConfig.Proto] = [.vless, .vmess, .trojan, .shadowsocks, .hysteria2, .wireguard, .socks]
    static let transports = ["tcp", "ws", "grpc", "xhttp", "httpupgrade", "kcp"]
    static let wrappers = ["none", "tls", "reality"]
    static let modes = ["auto", "packet-up", "stream-up", "stream-one"]
    /// The protocols that dial through the stream layer (a transport and a wrapper); the others carry their own.
    static func hasStream(_ p: MontanaVPNConfig.Proto) -> Bool { [.vless, .vmess, .trojan, .shadowsocks].contains(p) }
    /// The protocol's own name, as the rows print it.
    static func word(_ p: MontanaVPNConfig.Proto) -> String {
        switch p {
        case .vless: return "VLESS"
        case .vmess: return "VMess"
        case .trojan: return "Trojan"
        case .shadowsocks: return "Shadowsocks"
        case .hysteria2: return "Hysteria 2"   // NOT-UI: the protocol's own name
        case .wireguard: return "WireGuard"
        case .socks: return "SOCKS"
        case .unsupported: return p.rawValue
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Server") {
                    Picker("Protocol", selection: $c.proto) {
                        // USER-DATA: the protocols' own names, as the rows print them.
                        ForEach(Self.protocols, id: \.self) { p in Text(verbatim: Self.word(p)).tag(p) }
                    }
                    TextField("Name", text: $c.name)
                    field("Address", $c.host, .URL)
                    field("Port", $portText, .numberPad)
                }
                .listRowBackground(MTGlassRowPlate())
                Section("Credentials") { credentials }
                    .listRowBackground(MTGlassRowPlate())
                if Self.hasStream(c.proto) {
                    Section("Transport") { transport }
                        .listRowBackground(MTGlassRowPlate())
                    Section("Security") { security }
                        .listRowBackground(MTGlassRowPlate())
                }
            }
            .scrollContentBackground(.hidden)
            .montanaPageGround()
            .navigationTitle("New server")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { MontanaCloseMark { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    MontanaDoneMark { if let r = sealed { onSave(r); dismiss() } }.disabled(sealed == nil)
                }
            }
            .onChange(of: c.proto) { _, p in reset(p) }
        }
    }

    /// The secret and the words of the protocol chosen, each as the link parser names it.
    @ViewBuilder private var credentials: some View {
        switch c.proto {
        case .vless:
            field("UUID", $c.uuidOrPassword)
            field("Flow", $c.flow)
            field("Encryption", opt(\.encryption))
        case .vmess:
            field("UUID", $c.uuidOrPassword)
            field("Cipher", $c.method)
        case .trojan:
            field("Password", $c.uuidOrPassword)
        case .shadowsocks:
            field("Password", $c.uuidOrPassword)
            field("Cipher", $c.method)
        case .hysteria2:
            field("Password", $c.uuidOrPassword)
            field("SNI", $c.sni)
            field("Obfuscation password", opt(\.obfsPassword))
            field("Port hopping", opt(\.mport))
            field("Upload, Mbps", opt(\.up), .numberPad)
            field("Download, Mbps", opt(\.down), .numberPad)
            field("Pinned certificate SHA-256", opt(\.pinSHA256))
        case .wireguard:
            field("Private key", $c.uuidOrPassword)
            field("Public key", $c.publicKey)
            field("Pre-shared key", opt(\.presharedKey))
            field("Local IPs", opt(\.localIPs))
            field("MTU", $mtuText, .numberPad)
            field("Reserved", opt(\.reserved))
        case .socks:
            field("User", opt(\.user))
            field("Password", $c.uuidOrPassword)
        case .unsupported:
            EmptyView()
        }
    }
    /// The transport and what it carries: a path and a host for ws, httpupgrade and xhttp (and xhttp's mode), a service name
    /// for grpc, a seed for kcp; plain tcp carries nothing.
    @ViewBuilder private var transport: some View {
        Picker("Transport", selection: $c.network) {
            // USER-DATA: the transports' own names, as the engine names them.
            ForEach(Self.transports, id: \.self) { Text(verbatim: $0).tag($0) }
        }
        switch c.network {
        case "ws", "httpupgrade":
            field("Path", opt(\.path))
            field("Host header", opt(\.hostHeader))
        case "xhttp":
            field("Path", opt(\.path))
            field("Host header", opt(\.hostHeader))
            Picker("Mode", selection: Binding(get: { c.mode ?? "auto" }, set: { c.mode = $0 })) {
                // USER-DATA: the modes' own names, as the engine names them.
                ForEach(Self.modes, id: \.self) { Text(verbatim: $0).tag($0) }
            }
        case "grpc":
            field("Service name", opt(\.serviceName))
        case "kcp":
            field("Seed", opt(\.seed))
        default:
            EmptyView()
        }
    }
    /// The wrapper and its words: the name and the fingerprint under TLS and REALITY, ALPN under TLS, the server's key, the
    /// short id and SpiderX under REALITY.
    @ViewBuilder private var security: some View {
        Picker("Security", selection: $c.security) {
            // USER-DATA: the wrappers' own names, as the engine names them.
            ForEach(Self.wrappers, id: \.self) { Text(verbatim: $0).tag($0) }
        }
        if c.security != "none" {
            field("SNI", $c.sni)
            field("Fingerprint", $c.fingerprint)
        }
        if c.security == "tls" {
            field("ALPN", opt(\.alpn))
        }
        if c.security == "reality" {
            field("Public key", $c.publicKey)
            field("Short ID", $c.shortId)
            field("SpiderX", opt(\.spiderX))
        }
    }

    /// A technical field: no capitals, no correction, the keyboard for its kind.
    private func field(_ label: LocalizedStringKey, _ text: Binding<String>, _ keys: UIKeyboardType = .asciiCapable) -> some View {
        TextField(label, text: text)
            .keyboardType(keys).textInputAutocapitalization(.never).autocorrectionDisabled()
    }
    /// A word the record may not carry: an empty field is no word (nil) in the record.
    private func opt(_ kp: WritableKeyPath<MontanaVPNConfig, String?>) -> Binding<String> {
        Binding(get: { c[keyPath: kp] ?? "" }, set: { c[keyPath: kp] = $0.isEmpty ? nil : $0 })
    }
    /// The protocol chosen: the transport and the wrapper it dials with, as the link parser sets them.
    private func reset(_ p: MontanaVPNConfig.Proto) {
        switch p {
        case .hysteria2: c.network = "hysteria"; c.security = "tls"
        case .wireguard: c.network = "udp"; c.security = "none"
        case .socks: c.network = "tcp"; c.security = "none"
        default:
            if !Self.transports.contains(c.network) { c.network = "tcp" }
            if !Self.wrappers.contains(c.security) { c.security = "none" }
            if p == .trojan, c.security == "none" { c.security = "tls" }
        }
    }
    private var sealed: MontanaVPNConfig? { Self.sealed(c, port: portText, mtu: mtuText) }
    /// Pure: the record as it is kept, or nil while it cannot be dialled -- a machine, a port, the secret its protocol needs
    /// (WireGuard both keys, Shadowsocks its cipher, REALITY the server's key; SOCKS dials without one). Empty words are no
    /// words (nil), the name is the machine's when none was given, and a word of a section the protocol does not show is
    /// not kept: a wrapper's words without the wrapper, a transport's without the transport.
    static func sealed(_ draft: MontanaVPNConfig, port: String, mtu: String) -> MontanaVPNConfig? {
        var r = draft
        for kp in [\MontanaVPNConfig.host, \.uuidOrPassword, \.name, \.publicKey, \.shortId, \.sni, \.fingerprint, \.flow, \.method] {
            r[keyPath: kp] = r[keyPath: kp].trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !r.host.isEmpty, let p = UInt16(port.trimmingCharacters(in: .whitespaces)), 0 < p else { return nil }
        r.port = p
        switch r.proto {
        case .socks: break
        case .wireguard: guard !r.uuidOrPassword.isEmpty, !r.publicKey.isEmpty else { return nil }
        case .shadowsocks: guard !r.uuidOrPassword.isEmpty, !r.method.isEmpty else { return nil }
        case .unsupported: return nil
        default: guard !r.uuidOrPassword.isEmpty else { return nil }
        }
        let optional: [WritableKeyPath<MontanaVPNConfig, String?>] = [\.path, \.hostHeader, \.mode, \.extra, \.serviceName, \.spiderX, \.encryption, \.pqv, \.alpn,
                                                                     \.pinSHA256, \.headerType, \.seed, \.authority, \.obfsPassword, \.up, \.down, \.mport,
                                                                     \.presharedKey, \.localIPs, \.reserved, \.user]
        for kp in optional {
            let v = r[keyPath: kp]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            r[keyPath: kp] = v.isEmpty ? nil : v
        }
        r.mtu = r.proto == .wireguard ? Int(mtu.trimmingCharacters(in: .whitespaces)) : nil
        if hasStream(r.proto) {
            if r.security == "reality", r.publicKey.isEmpty { return nil }
            if r.security != "reality" { r.publicKey = ""; r.shortId = ""; r.spiderX = nil }
            if r.security == "none" { r.sni = ""; r.fingerprint = "" }
            if r.security != "tls" { r.alpn = nil }
            if !["ws", "httpupgrade", "xhttp"].contains(r.network) { r.path = nil; r.hostHeader = nil }
            if r.network != "xhttp" { r.mode = nil }
            if r.network != "grpc" { r.serviceName = nil }
            if r.network != "kcp" { r.seed = nil }
        }
        if r.name.isEmpty { r.name = r.host }
        return r
    }
}

/// THE VPN OF MONTANA'S NODES FOR TIME COINS (the author's words 05.10.2026 22:56-23:2x MSK: «instead of the button buy for 69 --
/// our button, as on the entrance page: pay with coins»; «for the VPN you pay x1 your current level in coins a second»; «the
/// tunnel mints in its own TimeChain; the payment for the VPN is its own TimeChain: our nodes give access to 1 device -- Amsterdam,
/// Frankfurt, Germany -- bound to the payment in Time Coins»). This phone holds a token only it knows, in the vault under the
/// device's key: a copy carries it nowhere, so the access is one device's. The nodes' door (montana-vpn-access) keeps sha256 of it
/// and one VLESS name of the device on every node. The tunnel is the one witness of its life (MTVPNWallMint): every living second
/// it counts -- the background's at the return -- burns a second's price in the payment's own chain (vpnpay), a minute at a time,
/// and every burn renews the device at the door for the door's credit. A short balance burns what it holds, stops the tunnel and
/// renews nothing; the door takes the device off when its credit ends.
/// THE HONEST BORDER: the coins live in this phone's book (MTChatMint, LOCAL TALLY); the door sees no balance and takes the
/// payment's word -- the core's wallet is the day it can check.
@MainActor final class MTVPNPay: ObservableObject {
    static let shared = MTVPNPay()
    nonisolated static let refPrefix = "vpnpay:"
    nonisolated static let planKey = "montana://vpn-pay"
    nonisolated static let tokenKey = "mt.vpn.payToken"   // NOT-UI: this device's own token (SeedScope.deviceKeys)
    static let door = URL(string: "https://api.montana.xxx/vpn-pay")
    /// The door's credit, renewed at every burn: three hours, the longest a device rides before its next burn renews it.
    static let credit = 10_800
    /// The tunnel's seconds owed are burned a minute at a time: one move of the book, one link of the chain.
    static let window = 60
    @Published private(set) var busy = false
    @Published private(set) var word: LocalizedStringKey?
    private var owed = 0

    /// THE PRICE OF A SECOND OF THE VPN (the author's word 06.10.2026 12:0x MSK: «the least price is 1 coin for 1 second, and then an
    /// automatic auction by the number of users, the number of nodes and the bandwidth of Montana's P2P network for the VPN»): one
    /// coin a second (MTCoinBook.price), the floor the auction will never go under. The auction is not built yet: until the network
    /// says its users, nodes and bandwidth, the floor is the price -- never the payer's level, which priced a richer person higher.
    static var perSecond: Int { MTCoinBook.price }
    nonisolated static func isPlan(_ url: String?) -> Bool { url == planKey }
    /// The tunnel stands on a row the coins pay for.
    static func rides(_ tunnel: MontanaVPNTunnel) -> Bool {
        tunnel.status == .connected && MontanaVPNStore.load().contains { c in c.subscription == planKey && c.id == tunnel.selectedId }
    }

    /// The hand asked for the VPN for coins: the door gives this device its rows, laid as Montana's plan and chosen. False -- not
    /// laid: no coin for a second, or no door answered; the page says which. The tunnel rises by the power's own road (toggleVPN).
    func prepare() async -> Bool {
        guard !busy else { return false }
        busy = true
        defer { busy = false }
        word = nil
        guard Self.perSecond <= MTCoinBook.ledger.balance else { word = "Not enough coins for the VPN"; return false }
        guard let links = await renew(coins: 0, ref: "") else { word = "The nodes did not answer"; return false }
        lay(links)
        guard let row = MontanaVPNStore.load().first(where: { c in c.subscription == Self.planKey }) else { return false }
        await MontanaVPNSelection.select(row, why: "pay")
        return true
    }

    /// The tunnel's fresh living seconds (MTVPNWallMint.take), owed while it stands on a paid row and burned a minute at a time.
    func charge(_ seconds: Int) {
        guard 0 < seconds, Self.rides(MontanaVPNTunnel.shared) else { return }
        owed += seconds
        guard Self.window <= owed else { return }
        let (coins, over) = Self.perSecond.multipliedReportingOverflow(by: owed)
        guard !over else { return }
        let ref = Self.refPrefix + String(Int64(Date().timeIntervalSince1970 * 1000)) + "-" + UUID().uuidString
        let burned = MTCoinBook.ledger.burn(coins, ref: ref)
        MontanaP2PTrace.markFolded("vpn_pay", "seconds=\(owed) coins=\(coins) burned=\(burned)", window: 60)
        owed = 0
        guard burned == coins else {
            word = "Coins ran out: the VPN of Montana's nodes is off"
            Task { await MontanaVPNTunnel.shared.stop(why: "the coins ran out") }
            return
        }
        Task { _ = await MTVPNPay.shared.renew(coins: burned, ref: ref) }
    }

    /// The door renews this device for its credit and answers its rows on every node that holds it; nil -- no answer.
    private func renew(coins: Int, ref: String) async -> [String]? {
        guard let door = Self.door, let t = Self.token(),
              let body = try? JSONSerialization.data(withJSONObject: ["t": t, "s": Self.credit, "c": coins, "h": ref]) else { return nil }
        var req = URLRequest(url: door, timeoutInterval: 30)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        guard let (data, response) = try? await URLSession.shared.data(for: req), (response as? HTTPURLResponse)?.statusCode == 200,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let links = obj["links"] as? [String], !links.isEmpty else {
            MontanaP2PTrace.mark("vpn_pay", "the door did not renew")
            return nil
        }
        return links
    }

    /// This device's token: 32 random bytes, born once and kept under the device's key.
    private static func token() -> String? {
        if let d = MontanaLocalVault.getDecrypted(tokenKey), let s = String(data: d, encoding: .utf8), s.count == 64 { return s }
        let s = montanaRandom(32).map { b in String(format: "%02x", b) }.joined()
        return MontanaLocalVault.setEncrypted(tokenKey, Data(s.utf8)) ? s : nil
    }

    /// The door's rows, laid as Montana's plan (planKey): never fetched as a subscription and never carried on the VPN wall -- the
    /// wall carries rows without a plan and plans of a web link alone (MTVPNWall.page), and these are one device's.
    private func lay(_ links: [String]) {
        var list = MontanaVPNStore.load()
        let old = list.filter { c in c.subscription == Self.planKey }
        list.removeAll { c in c.subscription == Self.planKey }
        var laid = 0
        for link in links {
            guard var c = MontanaVPNParse.parse(link) else { continue }
            c.subscription = Self.planKey
            c.uid = old.first(where: { o in o.host == c.host && o.port == c.port })?.uid ?? UUID().uuidString
            list.append(c)
            laid += 1
        }
        MontanaVPNStore.save(list)
        // USER-DATA: the nodes' own name, a proper name in every language
        MontanaVPNPlans.upsert(MontanaVPNPlan(url: Self.planKey, title: "Montana", updatedAt: Date().timeIntervalSince1970, count: laid))
    }
}
