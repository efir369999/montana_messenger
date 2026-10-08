import SwiftUI
import PhotosUI

// ════════════════════════════════════════════════════════════ PEER INFO — the screen. The only
// profile of a counterpart in the app: the header, the actions, the sections and the media panes.

struct MontanaPeerInfoScreen: View {
    let chat: Chat
    var onSave: (String, String, String?, String?, String?, [String]) -> Void = mtHandProfileEdit   // the one road (a page opened from the contacts too)

    @EnvironmentObject private var store: ChatStore
    @Environment(UIState.self) private var ui
    @StateObject private var state = MTPeerInfoState()
    @ObservedObject private var voice = VoicePlayer.shared   // the one player ([C-1]): the profile plays as the chat does
    @State private var showCardPicker = false
    @State private var report: MontanaReport? = nil   // Guideline 1.2: report this person
    @State private var awaitingLink = false            // «share contact» asked the peer for their link
    @State private var linkUnavailable = false
    @State private var selecting = false               // the profile's own selection of media (the author's word 15.09)
    @State private var selected: Set<MID> = []
    @State private var menuMessage: Message? = nil
    @State private var confirmBlock = false
    @State private var confirmLeave = false            // a member leaves the group, asked by the platform's own dialog (MTGroup.leave)
    @State private var removingSeat: String? = nil    // the owner takes a person out, asked first (MTGroup.remove)
    @State private var addingPeople = false           // the owner adds people from its correspondents (MTGroup.add)
    @State private var confirmDissolve = false        // the owner deletes the group for everyone, asked first (MTGroup.dissolve)
    @State private var roomAsk: MTRoomKind?           // the group's call chosen on its page: whom to invite (MTGroupRoom, 07.10)
    @State private var roomAskVideo = false
    @State private var originalNameShown = false     // the edit page: their own name revealed under the fields (20.09)
    @State private var aboutTick = 0                 // their bio or link arrived (24.09): the face's lines are asked again
    @State private var wallSheet: MTBoardSheet? = nil   // what the wall shows over the page (MTBoardPresenting, 25.09)
    @State private var wallPage: MTBoardRoute? = nil    // a writer's page, opened from the wall
    @StateObject private var face = MTFaceDock()   // the face starts at its circle and opens by a press -- the owner's rule for every page (24.09)
    @Environment(\.dismiss) private var dismiss
    private var letterCount: Int { (store.messages[chat.name]?.count ?? 0) + (chat.convId.flatMap { store.messages[$0]?.count } ?? 0) }

    private var data: MTPeerInfoData { MTPeerInfoData.resolve(chat: chat, store: store, state: state) }

    /// ONE PAGE, ONE DRESS WHEREVER IT OPENS (the author's word 25.09: «the page has one owner — nothing is redrawn»): the page
    /// wears its own tint, the chat's; pushed from the chats page it wore that page's gold and looked another page. Said here,
    /// around the screen, so the screen's long chain stays the one the compiler already reads.
    var body: some View { screen.tint(.primary) }
    @ViewBuilder private var screen: some View {
        let data = self.data
        // THE PAGE IS THE PLATFORM'S GROUPED LIST (the author's word 18.09: native, in the app's
        // grey, as every settings page): the face and the actions on the list's ground, the rows in
        // the list's grey groups with its own separators, the media strip and panes below.
        // SAVED MESSAGES IS ITS PANES (the author's word 18.09): the room without an address has no
        // face, no name and no actions to show — its page opens straight on the tab strip of media,
        // video, files, links, music and voices, with no title over it.
        let saved = ChatStore.isLocalRoom(chat.name)
        // A PERSON'S FACE IS THE ONE OWNER'S (the author's word 24.09): Settings' header (MTFaceDock),
        // above the list — the name under it on the left, their own words and their link under the
        // name with no caption over either — closing into the circle as the list is scrolled up, exactly as
        // in Settings. The edit page keeps its own header: a contact's photo is picked there.
        let faced = data.kind == .person && !state.editing && !saved
        let _ = aboutTick   // their bio or link arrived: the face's lines are asked again
        let about = faced ? MTPeerAbout.of(data.conv) : nil
        MTFacePage(face: face, shown: faced, glyph: data.initial, name: data.title,
                   blocked: store.blockedChats.contains(chat.name),
                   bio: about?.bio ?? "", link: MTPeerAbout.url(about?.link ?? ""), note: data.note,
                   of: data.kind == .person && !saved ? .peer(data.conv) : nil) { head in   // the ground they sent of their page (MTPageGround, 25.09), kept while the card is edited
            page(data, saved: saved, faced: faced, head: head)
        }
        // THE BARS OVER THE PAGE'S BOTTOM STAND OUTSIDE ITS ROWS (25.09): the rows sink into the ground at the window's
        // edges (MTPageEdges) and the bars do not -- as the chats page keeps its player over its rows.
        .safeAreaInset(edge: .bottom) { selectionBar }
        // THE MINI PLAYER STANDS HERE TOO (the author's word 18.09): the same bar as the chat's and the
        // list's, by reference — music and voices started on this page play in it, the queue this
        // correspondent's; a tap on the bar goes to the letter by the one road.
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                MontanaPlayerBar(onPlace: { t in dismiss(); ui.closeChat(); ui.askMusic(); MTMusicFocus.shared.show(t) },
                                 onSearch: { dismiss(); ui.closeChat(); ui.askMusic() },
                                 onGoTo: { c, f in
                    if c == chat.name, let mid = store.letterId(of: f, in: c) { dismiss(); ui.showLetter(chat, mid) }
                    else { NotificationCenter.default.post(name: .montanaGoToLetter, object: nil, userInfo: ["chat": c, "file": f]) }
                })
            }
        }
        // The same sheet as deleting a conversation from the list (the author's word 15.09): the
        // face, the question, the consequence in small type, the deed in red, «Cancel» apart.
        .overlay {
            if confirmBlock {
                MontanaBlockSheet(chat: chat,
                                  onBlock: { state.toggleBlocked(chat, store: store); confirmBlock = false },
                                  onCancel: { confirmBlock = false })
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .montanaPeerAboutArrived)) { n in
            if (n.userInfo?["conv"] as? String) == data.conv { aboutTick += 1 }
        }
        .onReceive(NotificationCenter.default.publisher(for: .montanaPeerLinkArrived)) { n in
            guard awaitingLink, (n.userInfo?["conv"] as? String) == data.conv, let link = MTPeerLinks.fresh(data.conv) else { return }
            awaitingLink = false
            MTShare.present([MTShare.web(link).map { $0 as Any } ?? MontanaConv.contactMessage(name: data.title, link: link)])
        }
        .alert("Asking for the contact link…", isPresented: $awaitingLink) { Button("Cancel", role: .cancel) { awaitingLink = false } }
        .alert("The contact link is not available yet: the person must open Montana once.", isPresented: $linkUnavailable) { Button("OK", role: .cancel) {} }
        .montanaPageGround()   // my page's ground, as every page wears it (rule 30, 25.09)
        .navigationTitle(state.editing ? "Edit" : "")   // no word over the face (the author's word 22.09)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(faced && face.dock == 2 ? .hidden : .automatic, for: .navigationBar)   // the whole screen is the face's
        .onChange(of: data.avatarFile, initial: true) { _, file in face.load(file: file) }
        .task(id: data.conv) { state.refreshConversation(chat: chat, store: store); state.bind(chat: chat, store: store) }
        .onChange(of: state.editing) { _, on in MontanaTrace.mark("profile_edit", on ? "on" : "off") }   // measured: the switch's moment
        .onChange(of: letterCount) { _, _ in state.refreshConversation(chat: chat, store: store) }
        .sheet(item: $report) { r in
            MontanaReportSheet(report: r, onBlock: { if !store.isBlocked(chat.name) { state.toggleBlocked(chat, store: store) } })
        }
        .fullScreenCover(item: $state.modal) { m in
            switch m {
            case .avatar:
                MontanaPhotoViewer(image: data.avatarFile.flatMap { UIImage(named: $0) ?? docImage($0) },
                                   fallbackColor: data.color, fallbackInitial: data.initial) { state.modal = nil }
            case .video(let f):
                Color.clear.onAppear {
                    VideoPresenter.present(f)
                    DispatchQueue.main.async { state.modal = nil }
                }
            }
        }
        .sheet(isPresented: $state.showFingerprint, onDismiss: { state.refreshVerified(data.conv) }) {
            SafetyNumberView(peerRef: data.conv, peerName: data.title)
        }
        .onChange(of: store.avatarFor(chat)) { _, live in
            // While the edit mode is open the draft wins: a photo just chosen or just cleared must not
            // be overwritten under the author's hands.
            if !state.editing { state.draftPhoto = live; state.refreshConversation(chat: chat, store: store) }
        }
        // A NAME ARRIVING LANDS ON THE OPEN PROFILE TOO (20.09): the page's data is a snapshot taken at
        // entry; the peer's word changes the store, and the snapshot follows it here.
        .onChange(of: store.peerNames[chat.convId ?? ""]) { _, _ in
            if !state.editing { state.refreshConversation(chat: chat, store: store) }
        }
        .onChange(of: state.pickerItem) { _, item in
            Task {
                if let bytes = try? await item?.loadTransferable(type: Data.self),
                   let ui = UIImage(data: bytes),
                   let jpeg = ui.avatarResized(400).jpegData(compressionQuality: 0.85),
                   let file = saveChatAvatar(jpeg) {
                    state.draftPhoto = file
                }
            }
        }
        .sheet(isPresented: $showCardPicker) {
            ContactPicker { card in state.attachToExistingCard(card, conv: chat.convId ?? "") }
                .ignoresSafeArea()
        }
        .toolbar {
            // THE DOTS STAND ALWAYS, TOP RIGHT, UPRIGHT (the author's word 18.09): one toolbar item on
            // every profile — not one that comes and goes with the right to edit — the one menu mark
            // with the platform's own menu behind it: edit when the profile is ours to edit, and the
            // profile's own actions, the very rows the sections draw ([C-1]: one list, two faces).
            ToolbarItem(placement: .topBarTrailing) {
                if state.editing {
                    MontanaDoneMark {
                        onSave(chat.id,
                               state.draftFirst.trimmingCharacters(in: .whitespaces),
                               state.draftLast.trimmingCharacters(in: .whitespaces),
                               state.draftNote.trimmingCharacters(in: .whitespaces),
                               state.draftPhoto,
                               state.draftMembers)
                        state.editing = false
                    }
                } else if data.canEdit {
                    MontanaEditMark {
                        MontanaTrace.mark("profile_edit", "tap")   // measured: the tap's moment (the author's word 18.09: «not at once»)
                        state.editing = true
                    }
                }
            }
        }
    }

    /// The page's own list — the actions, the rows, the panes — under the face when it stands (24.09).
    @ViewBuilder private func page(_ data: MTPeerInfoData, saved: Bool, faced: Bool, head: MTFacePageHead) -> some View {
        List {
            if faced {
                Section {
                    // THE FACE IS THE PAGE'S FIRST ROW (the author's word 25.09: «the whole page whole, scrolling as a full
                    // page»): as wide as the window, over the list's own side margin, and it scrolls away with the page.
                    head.padding(.horizontal, -MTPageEdge.side)
                    actions(data)
                        .frame(maxWidth: .infinity)
                        .background(MTScrollTouchesNow())   // a hold on an item begins at the touch (the author's word 15.09)
                        .background(face.probe)             // the list's pull opens the face and its scroll up closes it
                }
                .listRowBackground(Color.clear).listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 0, trailing: 0))
            } else if !saved { Section {
                VStack(spacing: 12) {
                    MTPeerHeader(source: .file(data.avatarFile),
                                 color: data.color,
                                 initial: data.initial,
                                 size: 100,
                                 title: state.editing ? nil : MontanaAvatar.spokenName(data.title),
                                 subtitle: nil,
                                 subtitleIsActive: data.subtitleIsActive,
                                 note: state.editing ? "" : data.note,
                                 blocked: store.blockedChats.contains(chat.name),
                                 showsCamera: state.editing,
                                 pickerItem: $state.pickerItem,
                                 onAvatarTap: { if !state.editing { state.modal = .avatar } })
                    if !state.editing { actions(data) }
                }
                .frame(maxWidth: .infinity)
                .background(MTScrollTouchesNow())   // a hold on an item begins at the touch (the author's word 15.09)
            }
            .listRowBackground(Color.clear).listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 0, trailing: 0))
            }
            if state.editing {
                editor(data)   // the platform's own grouped rows: fields, a photo row, a destructive row
            } else {
                if !saved { MTInfoSectionsView(sections: sections(data)) }
                Section { panes(data) }
                    .listRowBackground(Color.clear).listRowSeparator(.hidden).listRowInsets(EdgeInsets())
            }
        }
        .listStyle(.insetGrouped)
        // ONE EDGE FOR THE PAGE, WHEREVER IT OPENS (24.09, the author's word: «from the chat the tab strip stands further
        // right than on an ordinary opening — the posts' width and margins as on the page from the settings»). The list's
        // side margin is said here, the settings' own (MTPageEdge.side), so the chat's host, the list's stack and the
        // wall's own push lay the page out alike; the panes below take that margin as their edge — the strip, the posts
        // and the rows stand where My page's posts stand.
        .contentMargins(.horizontal, MTPageEdge.side, for: .scrollContent)
        .scrollContentBackground(.hidden)
        // THE WALL'S SHEETS AND PAGES RISE FROM THE LIST, never from one of its rows (the critic 25.09): a row the list lets
        // go takes its sheet and its destination with it.
        .modifier(MTBoardPresenting(sheet: $wallSheet, page: $wallPage))
        .modifier(MTGroupPageAsks(chat: chat, confirmLeave: $confirmLeave, removingSeat: $removingSeat, addingPeople: $addingPeople,
                                  confirmDissolve: $confirmDissolve, onGone: { dismiss(); ui.closeChat() }))
        .sheet(item: $roomAsk) { k in MTRoomInviteSheet(chat: chat.name, kind: k, video: roomAskVideo, opening: true) }
    }

    private func openVideo(_ f: String, _ data: MTPeerInfoData) { VideoPresenter.present(f) }
    private func openPicture(_ f: String) { PhotoPresenter.present(f, among: store.pictures(in: chat.name)) }

    // ── Sections ─────────────────────────────────────────────
    // The single place that decides which row belongs where. A section that collects nothing is not
    // drawn by the renderer, so a kind without an address simply contributes no rows.
    private func sections(_ data: MTPeerInfoData) -> [MTInfoSection: [MTInfoRow]] {
        var out: [MTInfoSection: [MTInfoRow]] = [:]

        // THE GROUP'S DESCRIPTION (the reference folder: the group page's info above its people): the owner's words, read by all
        if data.kind == .group, let about = MTGroup.shared.state(chat.name)?.about, !about.isEmpty {
            out[.about] = [MTInfoRow(id: "group.about", kind: .labeledValue(value: about, caption: "description"))]
        }
        if data.kind.showsMembers {
            var rows: [MTInfoRow] = [MTInfoRow(id: "members.header", kind: .header("MEMBERS"))]
            // The owner is the creator; a member's page names the owner first (MTGroup.pagePeople), the others by their own words.
            // The owner's page takes a person out (asked first) and adds people; a member's page offers to leave.
            let owns = MTGroup.shared.state(chat.name)?.mine == true
            let outside = MTGroup.shared.isOut(chat.name)
            let channel = MTGroup.shared.kind(chat.name) == .channel
            if owns {
                // «Add Member» heads the people, as the reference folder's group page has it
                rows.append(MTInfoRow(id: "members.add",
                                      kind: .action(title: "Add Member", icon: "person.badge.plus", destructive: false,
                                                    action: { addingPeople = true })))
                if !channel {
                    // THE GROUP'S INVITE LINK (stage R.6, the reference folder's «Invite Link»): the owner's card and the group's mark,
                    // handed by the system's sheet; a reset ends every link given before
                    rows.append(MTInfoRow(id: "members.link",
                                          kind: .action(title: "Invite Link", icon: "link", destructive: false,
                                                        action: { if let u = MTGroup.shared.inviteLink(chat.name) { MTShare.present([u]) } })))
                    rows.append(MTInfoRow(id: "members.linkReset",
                                          kind: .action(title: "Reset Invite Link", icon: "arrow.clockwise", destructive: false,
                                                        action: { MTGroup.shared.resetInvite(chat.name) })))
                }
            }
            // THE ROLES, AS THE REFERENCE'S MEMBER LIST NAMES THEM (stage R.6): owner, admin, member; the owner's hold on a person
            // names or dismisses an administrator and takes the person out; an administrator's hold takes out a member who is none.
            let myGroup = MTGroup.shared.state(chat.name)
            let iAdmin = !owns && myGroup.map { MTGroup.shared.isAdmin(chat.name, seat: $0.me) } == true
            rows.append(MTInfoRow(id: "members.me",
                                  kind: .member(name: String(localized: "You", bundle: MTLanguage.bundle),
                                                subtitle: owns ? "owner" : (iAdmin ? "admin" : "member"),
                                                removable: false,
                                                onRemove: {})))
            for m in MTGroup.shared.pagePeople(chat.name) {
                let theOwner = !owns && m.seat == MTGroup.ownerSeat
                let admin = MTGroup.shared.isAdmin(chat.name, seat: m.seat)
                let mayRemove = owns || (iAdmin && !theOwner && !admin)
                var deeds: [MTMemberDeed] = []
                if owns, !channel {
                    deeds.append(admin
                        ? MTMemberDeed(id: "dismiss", title: "Dismiss Admin", icon: "person.badge.minus") {
                            MTGroup.shared.setAdmin(chat.name, seat: m.seat, on: false, store: store) }
                        : MTMemberDeed(id: "promote", title: "Promote to Admin", icon: "person.badge.shield.checkmark") {
                            MTGroup.shared.setAdmin(chat.name, seat: m.seat, on: true, store: store) })
                }
                if mayRemove {
                    deeds.append(MTMemberDeed(id: "remove", title: "Remove from Group", icon: "person.fill.xmark", destructive: true) {
                        removingSeat = m.seat })
                }
                rows.append(MTInfoRow(id: "members.\(m.seat)",
                                      kind: .member(name: m.name,
                                                    subtitle: theOwner ? "owner" : (admin ? "admin" : "member"),
                                                    removable: mayRemove,
                                                    onRemove: { removingSeat = m.seat },
                                                    deeds: deeds)))
            }
            if owns, !channel {
                // the owner's way out is the group's end for everyone (the reference folder: «Delete Group», «Delete for All»)
                rows.append(MTInfoRow(id: "members.dissolve",
                                      kind: .action(title: "Delete Group", icon: "trash", destructive: true,
                                                    action: { confirmDissolve = true })))
            } else if !owns, !outside, MTGroup.shared.state(chat.name) != nil {
                rows.append(MTInfoRow(id: "members.leave",
                                      kind: .action(title: channel ? "Leave channel" : "Leave Group",
                                                    icon: "rectangle.portrait.and.arrow.right", destructive: true,
                                                    action: { confirmLeave = true })))
            }
            out[.members] = rows
        }

        if data.kind.showsRef {
            // A peer page holds neither an address nor a nickname: a person's profile is a name, a photo
            // and a callsign, exactly like our own ([C-1]). The address is never substituted here.
            var rows: [MTInfoRow] = []
            if data.hasFingerprint {
                rows.append(MTInfoRow(id: "info.fingerprint",
                                      kind: .disclosure(title: "Fingerprint verification",
                                                        detail: state.isVerified ? "Identity verified" : "Not verified",
                                                        icon: state.isVerified ? "checkmark.shield.fill" : "shield.lefthalf.filled",
                                                        tint: state.isVerified ? .green : .gray,   // grey until verified (18.09)
                                                        action: { state.showFingerprint = true })))
            }
            // 15.11 / 15.09: the correspondent's own daily code, handed to us to hand on. The row
            // stands on EVERY profile (the author's word): with a fresh link it shares at once;
            // without one it asks the peer for theirs and shares the moment it arrives.
            rows.append(MTInfoRow(id: "info.shareContact",
                                  kind: .action(title: "Share contact", icon: "square.and.arrow.up",
                                                destructive: false,
                                                action: { shareContact(data) })))
            out[.peerInfo] = rows
        }

        var settings: [MTInfoRow] = []
        // Adding goes through the contacts tab's own save path, so the card lands in the phone's
        // address book and the row appears on the Contacts tab — one way of creating a contact,
        // by hand, from wherever the person is standing.
        if data.kind.showsBlock, !state.isInContacts(data.conv) {
            settings.append(MTInfoRow(id: "settings.newContact",
                                      kind: .action(title: "Create new contact", icon: "person.crop.circle.badge.plus",
                                                    destructive: false,
                                                    action: { state.addToContacts(conv: data.conv, title: data.title) })))
            settings.append(MTInfoRow(id: "settings.existingContact",
                                      kind: .action(title: "Add to existing", icon: "person.crop.circle.badge.checkmark",
                                                    destructive: false,
                                                    action: { showCardPicker = true })))
        }
        if data.kind.showsBlock {
            settings.append(MTInfoRow(id: "settings.report",
                                      kind: .action(title: "Report", icon: "exclamationmark.bubble",
                                                    destructive: true,
                                                    action: { report = MontanaReport(peer: chat.convId ?? chat.name, peerName: data.title, text: "", mid: "") })))
            settings.append(MTInfoRow(id: "settings.block",
                                      kind: .action(title: state.isBlocked ? "Unblock" : "Block",
                                                    icon: state.isBlocked ? "hand.raised.fill" : "hand.raised",
                                                    destructive: true,
                                                    action: {
                                                        if store.blockedChats.contains(chat.name) { state.toggleBlocked(chat, store: store) }
                                                        else { confirmBlock = true }   // the platform's own confirmation first
                                                    })))
        }
        out[.chatSettings] = settings

        return out
    }

    private func shareContact(_ data: MTPeerInfoData) {
        if let link = MTPeerLinks.fresh(data.conv) {
            MTShare.present([MTShare.web(link).map { $0 as Any } ?? MontanaConv.contactMessage(name: data.title, link: link)])
            return
        }
        awaitingLink = true
        E2E.shared.askLinkWord(from: data.conv)
        // A peer that does not answer within a few seconds is asleep or older: said honestly.
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
            if awaitingLink { awaitingLink = false; linkUnavailable = true }
        }
    }

    /// The profile's menu on a letter: the chat's cloud, the profile's rows.
    private func openMenu(_ m: Message) {
        let close: () -> Void = { MontanaOverlayWindow.shared.hide(); menuMessage = nil }
        menuMessage = m
        MontanaOverlayWindow.shared.show {
            MessageContextOverlay(
                message: m, isPinned: false, canEdit: false, player: voice,
                onReact: { _ in close() }, onReply: close, onCopy: close, onEdit: close, onPin: close,
                onForward: { close(); ui.pendingForward = m.id; dismiss(); DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { ui.openChat(chat) } },
                onSelect: { close(); selecting = true; selected = [m.id] },
                // The chat beneath this profile is already open: opening it again changes nothing
                // the feed watches (measured 15.09: «show in chat» closed the profile and stood
                // still). The jump is the one record the feed watches (ui.overlayJump); it is
                // cleared first so the same letter can be asked for twice.
                // The chat beneath this profile is already open: opening it again changes nothing
                // the feed watches (measured 15.09: «show in chat» closed the profile and stood
                // still; a record that happened to hold the same letter did not change either).
                // An EVENT is heard every time it is posted — the open feed jumps on it.
                onShowInChat: {
                    close(); dismiss()
                    MontanaTrace.mark("jump_ask", "chat=\(String(chat.name.prefix(10))) mid=\(String(m.id.description.prefix(12)))")
                    ui.showLetter(chat, m.id)   // the one road: the chat beneath jumps, a closed one opens at the letter
                },
                canDeleteForEveryone: false, ladder: false,
                onDeleteMine: { store.deleteLocally(chat: chat.name, m); close() },
                onDeleteEveryone: close,
                onClose: close)
        }
    }

    /// A media item of the profile: a tap opens it, a hold opens the menu, in selection mode a
    /// tap toggles the mark. Every pane wears the same law (one modifier, MTProfileItem).
    private func itemLaw(_ m: Message, open: @escaping () -> Void) -> MTProfileItem {
        MTProfileItem(selecting: selecting, isSelected: selected.contains(m.id),
                      toggle: { if selected.contains(m.id) { selected.remove(m.id) } else { selected.insert(m.id) } },
                      open: open, menu: { openMenu(m) })
    }
    private func item<V: View>(_ m: Message, open: @escaping () -> Void, @ViewBuilder _ body: () -> V) -> some View {
        body().modifier(itemLaw(m, open: open))
    }

    /// The selection bar: forward through the chat's own picker, delete for me.
    @ViewBuilder private var selectionBar: some View {
        if selecting {
            HStack {
                Button { selecting = false; selected = [] } label: {
                    Image(systemName: "xmark").font(.system(size: 17, weight: .semibold))
                        .foregroundColor(MontanaOctagon.barGlyph)
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .accessibilityLabel(Text("Cancel"))
                Spacer()
                Text("\(selected.count)").foregroundColor(.gray).monospacedDigit()
                Spacer()
                Button {
                    let mids = Array(selected); selecting = false; selected = []
                    ui.pendingForwardMany = mids; dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { ui.openChat(chat) }
                } label: {
                    Image(systemName: "arrowshape.turn.up.right")
                        .foregroundColor(selected.isEmpty ? .gray : Color.accentColor)
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .disabled(selected.isEmpty)
                Button {
                    for m in (store.messages[chat.name] ?? []).filter({ selected.contains($0.id) }) { store.deleteLocally(chat: chat.name, m) }
                    selecting = false; selected = []
                } label: {
                    Image(systemName: "trash").foregroundColor(selected.isEmpty ? .gray : .red)
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .disabled(selected.isEmpty)
                .padding(.leading, 18)
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(.ultraThinMaterial)
        }
    }

    // ── Actions under the header ─────────────────────────────
    // The actions under the header, the platform's own bordered buttons in the app's grey (the
    // author's word 18.09): the glyph over the word, the words the chat's menu uses.
    /// FOUR PLATES OF ONE SIZE, THE GLYPH ALONE (the author's word 22.09): no word under the glyph — the
    /// glyph says it, and the platform's accessibility label speaks it; every plate takes an equal share of
    /// the row at one height (the touch target's), «More» among them in the same dress.
    private func actions(_ data: MTPeerInfoData) -> some View {
        HStack(spacing: 10) {
            ForEach(pageActions(data)) { action in
                if action == .more {
                    // «MORE» IS THE PLATFORM'S MENU (the author's word 22.09): the same plate as its neighbours,
                    // the system's menu behind it — the chat's wallpaper, chosen and previewed before it is set.
                    Menu {
                        Button { ui.chatWall = MTWallOpen(id: chat.convId ?? chat.name) } label: { Label("Chat background", systemImage: "photo") }   // a page over everything, closed by the swipe from the left (23.09)
                    } label: {
                        actionFace(action)
                    }
                    .menuStyle(.button)
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(action.title))
                } else {
                    Button { perform(action, data) } label: {
                        actionFace(action)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(action.title))
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 6)
    }
    /// The page's actions: a person's as they were; a group where calls are made (MTGroupRoom.kinds) adds its voice and video chat
    /// beside the message -- the same plates, the group's own room behind them.
    private func pageActions(_ data: MTPeerInfoData) -> [MTPeerAction] {
        let base = MTPeerAction.available(for: data.kind, blocked: store.blockedChats.contains(chat.name))
        guard data.kind == .group, MTGroupRoom.shared.kinds(for: chat.name).contains(.call) else { return base }
        return [.message, .audioCall, .videoCall] + base.filter { $0 != .message }
    }
    /// THE PLATE IS THE SYSTEM'S ONE-TONE GLASS (the author's word 25.09: «the buttons message, calls, video, more -- all on the
    /// system's one-tone liquid glass»): the bar's own octagon plate, the touch target's height, the glyph the bar's.
    private func actionFace(_ action: MTPeerAction) -> some View {
        Image(systemName: action.icon).font(.system(size: 20, weight: .medium)).foregroundColor(.primary)
            .frame(maxWidth: .infinity)
            .montanaOctagonFace(bar: true, height: montanaTouchTarget)
            .contentShape(Rectangle())
    }

    // Each header action performs its own thing — a screen that only announces «not yet» is a
    // screen that lies about what it offers.
    private func perform(_ action: MTPeerAction, _ data: MTPeerInfoData) {
        switch action {
        case .message:
            // Opened from the contacts tab there is no conversation on screen yet; opened from the
            // chat there already is, and re-opening it would flash. Close the profile either way.
            let alreadyOpen = ui.overlayChat?.convId ?? "" == chat.convId ?? ""
            dismiss()
            if !alreadyOpen { DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { ui.openChat(chat) } }
        case .audioCall where data.kind == .group, .videoCall where data.kind == .group:
            // a group's call: its room, or whom to invite into a new one (MTGroupRoom.tapped -- the chat's top answers the same)
            MTGroupRoom.shared.tapped(chat.name, kind: .call, video: action == .videoCall) { k, v in roomAskVideo = v; roomAsk = k }
        case .audioCall:
            MontanaCall.shared.startCall(peer: data.conv, device: "", video: false,
                displayName: MTNameBook.display(conv: data.conv))
        case .videoCall:
            MontanaCall.shared.startCall(peer: data.conv, device: "", video: true,
                displayName: MTNameBook.display(conv: data.conv))
        case .more:
            break   // the menu answers itself
        }
    }

    // ── Edit mode ────────────────────────────────────────────
    /// THE EDIT PAGE IS THE PLATFORM'S (the author's word 18.09: native fields, native colours, native
    /// buttons — nothing of ours). The rows are the grouped list's own: text fields in a section with
    /// the system's placeholder, colour and caret; the photo as a row that opens the system picker;
    /// the removal as the system's destructive row. No plate, no colour, no font of ours is added;
    /// the rows stand on the platform's own glass (MTGlassRowPlate) with the page's ground under them (25.09).
    @ViewBuilder private func editor(_ data: MTPeerInfoData) -> some View {
        if data.kind == .group {
            Section {
                TextField("Title", text: $state.draftFirst)
                    .textContentType(.organizationName)
                    .textInputAutocapitalization(.words)
            }
            .listRowBackground(MTGlassRowPlate())   // the editor's rows on the one glass, the page's ground under them (25.09)
            if MTGroup.shared.manages(chat.name) {
                // THE DESCRIPTION, AS THE REFERENCE'S GROUP EDITOR HAS IT: written by the owner, carried to every member (MTGroup.renew)
                Section {
                    TextField("Description", text: $state.draftNote, axis: .vertical)
                        .lineLimit(1...5)
                } footer: {
                    Text("You can provide an optional description for your group.")
                }
                .listRowBackground(MTGlassRowPlate())
            }
        } else {
            // WHOSE NAME, WHOSE FACE (the author's word 20.09): only here, on the edit page, and only
            // where this person's hand stands over the correspondent's own word — a button under the
            // name fields shows the name they gave themselves; under the note, the photo they
            // published stands when the one on the card was set by hand. The profile page itself
            // says nothing of it. One reader for both answers: the name book.
            let conv = data.conv
            let theirName = MTNameBook.declared[conv].flatMap { $0.isEmpty ? nil : $0 }
            let overName = MTNameBook.mine(conv) != nil && theirName != nil
            Section {
                TextField("First name", text: $state.draftFirst)
                    .textContentType(.givenName)
                    .textInputAutocapitalization(.words)
                TextField("Last name", text: $state.draftLast)
                    .textContentType(.familyName)
                    .textInputAutocapitalization(.words)
                if overName {
                    Button("Show original name") { originalNameShown.toggle() }
                }
            } footer: {
                if overName, originalNameShown, let t = theirName {
                    Text(verbatim: t)   // USER-DATA: the name they gave themselves
                }
            }
            .listRowBackground(MTGlassRowPlate())
            let theirPhoto = MTNameBook.uniquePublishedPhoto(conv, files: store.peerAvatars)
            Section {
                TextField("Note", text: $state.draftNote, axis: .vertical)
                    .lineLimit(1...5)
                // THE ORIGINAL FACE COMES BACK BY ONE TAP (the author's word 20.09): whenever my own
                // picture stands on the card — saved earlier or just picked — the row shows their own
                // face (the photo they published, or their glyph when they published none) and puts it
                // back into the draft; «Done» then hands their own word to the book, which is not a pin
                // by the one writer's rule (setManualPhoto).
                if let mine = state.draftPhoto, mine != theirPhoto {
                    Button { state.draftPhoto = theirPhoto } label: {
                        HStack(spacing: 12) {
                            AvatarCircle(photoURL: theirPhoto, color: chat.color, initial: data.initial, size: 36)
                            Text("Restore original photo")
                        }
                    }
                }
            }
            .listRowBackground(MTGlassRowPlate())
        }
    }

    // ── Media panes ──────────────────────────────────────────
    /// NEWEST ON TOP, CUT BY DAY (the author's word 18.09) — on every pane alike: the conversation
    /// comes oldest first, the panes read it backwards, and the day's word is the feed's own (MTDayLabel).
    struct MTDaySection: Identifiable { let id: String; let items: [Message] }
    private func byDay(_ items: [Message]) -> [MTDaySection] {
        var out: [MTDaySection] = []
        for m in items.reversed() {
            let d = MTDayLabel.of(m.createdAt)
            if let last = out.last, last.id == d { out[out.count - 1] = MTDaySection(id: d, items: last.items + [m]) }
            else { out.append(MTDaySection(id: d, items: [m])) }
        }
        return out
    }
    private func dayHeader(_ s: String) -> some View {
        // USER-DATA: the day's word.
        Text(verbatim: s).font(.caption).foregroundColor(.gray)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16).padding(.top, 12)
    }
    @ViewBuilder private func panes(_ data: MTPeerInfoData) -> some View {
        MTTabStrip(tab: $state.tab).frame(height: 52).padding(.top, 4)   // UIKit's own strip, 44 pt tall — the finger lands first time (18.09)
            .background(MTSwipePanes(onNext: { turnPane(+1) }, onBack: { turnPane(-1) }))
            .background(MTEdgeMark("tab-strip"))   // where the strip stands across the screen, said to the diary (24.09)
            // THE LOOK ASKS (the author's word 25.09: «entering the page must show the wall to everyone, at once»): the page asks
            // for the person's wall as it opens — the held page is drawn at once, the owner's fresh one takes its place (MTBoard.look).
            .onAppear { if data.kind == .person { MTBoard.shared.look(data.conv) } }

        let items = data.pane(state.tab)
        // THE WALL (the author's word 24.09): a person's page shows their wall; Saved Messages is my own page, so its
        // wall is mine; a group has none.
        if state.tab == .wall, ChatStore.isLocalRoom(chat.name) || data.kind == .person {
            // THE WALL'S POSTS ARE THE LIST'S OWN ROWS (the critic 25.09, the author's screenshot: a hole between the tabs and
            // «Write on the wall»): one cell per post, each measured by itself; the list's margin is the wall's edge (24.09).
            MTBoardRows(owner: ChatStore.isLocalRoom(chat.name) ? nil : data.conv, edge: 0, sheet: $wallSheet, page: $wallPage)
        } else if items.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: state.tab.icon)
                    .font(.system(size: 42)).foregroundColor(.gray)
                Text(state.tab.emptyText).foregroundColor(.gray).font(.subheadline)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 36)
        } else {
            // The music queue is the whole pane in feed order, whichever day the tap lands in.
            let tracks: [MusicTrack] = items.compactMap { m in
                m.docFile.map { MusicTrack(file: $0, title: m.docName ?? $0, msgId: m.id, chat: chat.name, chatTitle: data.title) }
            }
            ForEach(byDay(items)) { sec in
                dayHeader(sec.id)
                switch state.tab {
                case .wall: EmptyView()
                case .media: grid(sec.items, data) { $0.imageFile }
                case .video: videoGrid(sec.items, data)
                case .files: fileList(sec.items)
                case .links: linkList(sec.items)
                case .music: musicList(sec.items, tracks: tracks)
                case .voice: voiceList(sec.items)
                }
            }
        }
    }

    /// THE PROFILE WEARS THE PLAYER'S DRESS (the author's word 22.09): a file, a link, a track and a
    /// voice each stand on the bar's own glass — the square plate with the glyph and the long plate
    /// with the words, ten points apart, exactly as the mini player and the message row stand. No grey
    /// card, no divider, no gold: the glass carries the ground through it and the glyph is the bar's.
    static let rowHeight: CGFloat = 56
    private func glassRow(glyph: String, @ViewBuilder _ words: () -> some View) -> some View {
        HStack(spacing: 10) {
            Image(systemName: glyph)
                .font(.system(size: 17, weight: .semibold)).foregroundColor(MontanaOctagon.barGlyph)
                .montanaOctagonFace(square: true, bar: true, height: Self.rowHeight)
            HStack(spacing: 10) { words() }
                .frame(maxWidth: .infinity)
                .montanaOctagonFace(bar: true, height: Self.rowHeight)
        }
    }
    /// One step along the strip, stopping at its ends — the strip itself follows the tab.
    private func turnPane(_ step: Int) {
        let all = MTMediaTab.allCases
        guard let i = all.firstIndex(of: state.tab) else { return }
        let j = i + step
        guard j >= 0, j < all.count else { return }
        withAnimation(.easeInOut(duration: 0.2)) { state.tab = all[j] }
    }
    /// THE TILES STAND THREE TO A ROW, EACH ROW ONE OF THE LIST'S OWN (the critic 25.09, the hole under the tabs): a lazy grid
    /// inside one row of the page's list gave that row a height guessed before its tiles stood, and the list centred what it
    /// held in it. A day's tiles are cut into rows of three — the last filled out with empty room — and the list measures
    /// every row by itself, on any phone.
    struct MTTileRow: Identifiable { let id: String; let items: [Message]; let first: Bool }
    private func threes(_ items: [Message]) -> [MTTileRow] {
        stride(from: 0, to: items.count, by: 3).map { i in
            let part = Array(items[i..<min(i + 3, items.count)])
            return MTTileRow(id: part[0].id, items: part, first: i == 0)
        }
    }
    /// One row of three tiles, each a third of the width, 120 points tall.
    private func tileRow<V: View>(_ row: MTTileRow, _ tile: @escaping (Message) -> V) -> some View {
        HStack(spacing: 3) {
            ForEach(row.items) { m in tile(m).frame(maxWidth: .infinity) }
            ForEach(row.items.count..<3, id: \.self) { _ in Color.clear.frame(maxWidth: .infinity).frame(height: 120) }
        }
        .padding(.horizontal, 2).padding(.top, row.first ? 8 : 3)
    }
    @ViewBuilder private func grid(_ items: [Message], _ data: MTPeerInfoData, _ file: @escaping (Message) -> String?) -> some View {
        ForEach(threes(items.filter { file($0) != nil })) { row in
            tileRow(row) { m in
                item(m, open: { openPicture(file(m) ?? "") }) {
                    MTCover(file: file(m) ?? "", ready: docImageCached(file(m) ?? ""), isVideo: false, side: 180)   // born off the main thread (18.09), at the cell's pixels (25.09)
                        .frame(maxWidth: .infinity).frame(height: 120).clipped()
                }
            }
        }
    }

    @ViewBuilder private func videoGrid(_ items: [Message], _ data: MTPeerInfoData) -> some View {
        ForEach(threes(items.filter { $0.videoFile != nil })) { row in
            tileRow(row) { m in
                item(m, open: { openVideo(m.videoFile ?? "", data) }) {   // a video and a round note in the system's player (29.09)
                    ZStack {
                        VideoGridThumb(file: m.videoFile ?? "").frame(height: 120).clipped()
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 28)).foregroundColor(.white.opacity(0.9))
                    }
                    .frame(maxWidth: .infinity).frame(height: 120).clipped()
                }
            }
        }
    }

    private func fileList(_ items: [Message]) -> some View {
        VStack(spacing: 8) {
            ForEach(items) { m in
                if let f = m.docFile {
                    glassRow(glyph: "doc") {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(m.docName ?? String(localized: "File", bundle: MTLanguage.bundle)).foregroundColor(.white).lineLimit(1)
                            Text(fileSizeString(f)).font(.caption).foregroundColor(.gray)
                        }
                        Spacer(minLength: 0)
                        Text(m.time).font(.caption2).foregroundColor(.gray)
                    }
                    .modifier(itemLaw(m, open: { ui.docPage = MTDocOpen(id: f, name: m.docName ?? f) }))
                }
            }
        }
        .padding(.top, 8)   // the list's margin is the rows' edge, as the wall's (24.09)
    }

    // Every link of every letter; a tap opens it in the system's default browser (the author's
    // word 18.09: no browser of ours yet).
    private func linkList(_ items: [Message]) -> some View {
        VStack(spacing: 8) {
            ForEach(items) { m in
                ForEach(MTLinks.urls(in: m.text), id: \.absoluteString) { u in
                    glassRow(glyph: "link") {
                        VStack(alignment: .leading, spacing: 2) {
                            // USER-DATA: the link's host and the link itself.
                            Text(verbatim: u.host ?? u.absoluteString).foregroundColor(.white).lineLimit(1)
                            Text(verbatim: u.absoluteString).font(.caption).foregroundColor(.gray).lineLimit(1).truncationMode(.middle)
                        }
                        Spacer(minLength: 0)
                        Text(m.time).font(.caption2).foregroundColor(.gray)
                    }
                    .modifier(itemLaw(m, open: { UIApplication.shared.open(u) }))
                }
            }
        }
        .padding(.top, 8)   // the list's margin is the rows' edge, as the wall's (24.09)
    }

    // The chat's music: a tap plays it through the one player, the chat's music as the queue.
    private func musicList(_ items: [Message], tracks: [MusicTrack]) -> some View {
        let player = VoicePlayer.shared
        return VStack(spacing: 8) {
            ForEach(items) { m in
                if let f = m.docFile {
                    glassRow(glyph: player.playingFile == f && !player.paused ? "pause.fill" : "play.fill") {
                        VStack(alignment: .leading, spacing: 2) {
                            // USER-DATA: the track's own name.
                            Text(verbatim: ((m.docName ?? f) as NSString).deletingPathExtension).foregroundColor(.white).lineLimit(1)
                            Text(fileSizeString(f)).font(.caption).foregroundColor(.gray)
                        }
                        Spacer(minLength: 0)
                        Text(m.time).font(.caption2).foregroundColor(.gray)
                    }
                    .modifier(itemLaw(m, open: {
                        if player.playingFile == f { if player.paused { player.resume() } else { player.pause() }; return }
                        player.queue = tracks
                        if let i = tracks.firstIndex(where: { $0.file == f }) { player.play(index: i) }
                    }))
                }
            }
        }
        .padding(.top, 8)   // the list's margin is the rows' edge, as the wall's (24.09)
    }

    /// The profile's voices play as the chat's do ([C-1], the author's word 18.09): the one player,
    /// this correspondent's voices in feed order behind the one tapped, auto-next along them. The
    /// row is drawn, not a button: a button inside the item law fought the item's own tap.
    private func playVoice(_ file: String, among items: [Message]) {
        let p = VoicePlayer.shared
        if p.playingFile == file { if p.paused { p.resume() } else { p.pause() }; return }
        let queue: [(file: String, sender: String, mine: Bool)] = items.compactMap { m in   // feed order: auto-next walks forward
            guard let a = m.audioFile, fileOnDisk(a) else { return nil }
            return (a, m.isFromMe ? E2E.myDisplayName() : store.displayName(for: m.senderRef ?? chat.convId ?? chat.name), m.isFromMe)
        }
        p.playVoice(file, sender: queue.first { $0.file == file }?.sender ?? "", chat: chat.name, queue: queue)
    }
    private func voiceList(_ items: [Message]) -> some View {
        let all = data.pane(.voice)
        return VStack(spacing: 8) {
            ForEach(items) { m in
                if let af = m.audioFile {
                    glassRow(glyph: voice.playingFile == af && !voice.paused ? "pause.fill" : "play.fill") {
                        Text("Voice message").foregroundColor(.white)
                        Spacer(minLength: 0)
                        Text(fmtDuration(m.audioDuration)).font(.caption).foregroundColor(.gray)
                        Text(m.time).font(.caption2).foregroundColor(.gray)
                    }
                    .modifier(itemLaw(m, open: { playVoice(af, among: all) }))
                }
            }
        }
        .padding(.top, 8)   // the list's margin is the rows' edge, as the wall's (24.09)
    }
}

/// THE ITEM LAW of the profile's panes (the author's word 15.09, one modifier for every pane):
/// the hit area is the frame — never a picture's overflow past its clip (measured 15.09: a tap
/// on «Block» opened a photo that overflowed the grid above it); a tap opens, a hold opens the
/// chat's menu, in selection mode a tap toggles the mark and the mark is drawn in the corner.
struct MTProfileItem: ViewModifier {
    let selecting: Bool
    let isSelected: Bool
    let toggle: () -> Void
    let open: () -> Void
    let menu: () -> Void
    @State private var pressed = false
    @State private var menuFiredThisPress = false
    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .overlay(alignment: .topTrailing) {
                if selecting {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22)).foregroundColor(isSelected ? Color.accentColor : .white)
                        .padding(6)
                }
            }
            // THE CHAT'S TOUCH, ONE TO ONE (the author's word 15.09; MessageBubble.bubbleUnderFinger):
            // the hold owns the touch and answers at the same threshold the finger gets its
            // response; the tap is secondary and yields when this very touch opened the menu.
            // A tap gesture standing FIRST made the hold wait for the tap to fail — the menu came late.
            .scaleEffect(pressed ? 0.965 : 1)
            .animation(.easeOut(duration: 0.15), value: pressed)
            .onLongPressGesture(minimumDuration: montanaLongPress, maximumDistance: 12) {
                menuFiredThisPress = true
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                menu()
            } onPressingChanged: { p in
                pressed = p
                if p { menuFiredThisPress = false }   // a new touch — a clean session
            }
            .simultaneousGesture(TapGesture().onEnded {
                if menuFiredThisPress { return }   // this touch opened the menu — release does not trigger content
                if selecting { toggle() } else { open() }
            })
    }
}

/// THE SCROLL'S GRACE, LIFTED (the author's word 15.09: the profile's hold must answer as fast
/// as the chat's). A scrolling container holds every touch for a moment to tell a scroll from
/// a press; the chat's feed does not, so its menu opens on the hold itself. This view, placed
/// inside the profile's scroll, asks that one container — its own — to hand touches over at
/// once. One property on one view of ours, set when the view lands; nothing patrols.
/// THE TABS ROLL BY THE PANEL ITSELF (the author's word 18.09: the strip must scroll under the
/// finger, and no glass segment may fire under it). The strip is a plain scroll view with the tab
/// words laid inside it as labels and ONE tap recogniser over the whole strip; nothing inside the
/// strip is a control, so a finger that moves is the scroll view's own pan and a finger that stays
/// is the tap — the platform tells them apart, we add nothing. The selection is a rounded fill that
/// slides under the chosen word. While the words fit the screen they share the width evenly; when
/// they do not, each keeps the width of its word and the strip rolls, the chosen word riding into
/// view with a hundred points of lookahead.
struct MTTabStrip: UIViewRepresentable {
    @Binding var tab: MTMediaTab
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    final class Track: UIScrollView {
        /// The scroll view's own hook: a touch begun over a word may become the scroll.
        override func touchesShouldCancel(in view: UIView) -> Bool { true }
    }
    final class Strip: UIView {
        let track = Track()
        let glass: UIVisualEffectView = {
            if #available(iOS 26.0, *) { return UIVisualEffectView(effect: UIGlassEffect()) }
            return UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
        }()
        let pill = UIView()
        var labels: [UILabel] = []
        var slots: [CGRect] = []          // each tab's target and fill, in the track's content
        var selected = 0
        var onSelect: ((Int) -> Void)?
        override init(frame: CGRect) {
            super.init(frame: frame)
            track.delaysContentTouches = false
            track.canCancelContentTouches = true
            track.showsHorizontalScrollIndicator = false
            track.showsVerticalScrollIndicator = false
            track.alwaysBounceHorizontal = false
            track.alwaysBounceVertical = false
            track.clipsToBounds = true
            // THE STRIP STANDS ON THE SYSTEM'S ONE-TONE GLASS (the author's word 25.09: «the tab strip too -- the system's one-tone
            // liquid glass»): the platform's own glass effect behind the track where the system has it, its blur before.
            track.backgroundColor = .clear
            glass.isUserInteractionEnabled = false
            glass.clipsToBounds = true
            addSubview(glass)
            pill.backgroundColor = .systemGray4
            track.addSubview(pill)
            addSubview(track)
            for t in MTMediaTab.allCases {
                let l = UILabel()
                l.text = t.name
                l.font = .systemFont(ofSize: 15, weight: .medium)
                l.textAlignment = .center
                l.textColor = .secondaryLabel
                l.isUserInteractionEnabled = false
                track.addSubview(l)
                labels.append(l)
            }
            addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped(_:))))
        }
        required init?(coder: NSCoder) { nil }
        override func layoutSubviews() {
            super.layoutSubviews()
            let h: CGFloat = 44   // the platform's minimum touch target
            // The strip stands on its row's own edge: the page's margin places the row (24.09) — a second inset of its
            // own put the strip 16 points further in than the posts under it.
            track.frame = CGRect(x: 0, y: (bounds.height - h) / 2, width: bounds.width, height: h)
            track.layer.cornerRadius = h / 2
            glass.frame = track.frame
            glass.layer.cornerRadius = h / 2
            pill.layer.cornerRadius = (h - 6) / 2
            let widths = labels.map { ceil($0.intrinsicContentSize.width) + 32 }
            let inner = track.bounds.width - 6
            var x: CGFloat = 3
            slots = []
            if widths.reduce(0, +) <= inner {
                let w = floor(inner / CGFloat(labels.count))
                for (i, l) in labels.enumerated() {
                    let sw = i == labels.count - 1 ? inner - w * CGFloat(labels.count - 1) : w
                    let slot = CGRect(x: x, y: 3, width: sw, height: h - 6)
                    slots.append(slot); l.frame = slot; x += sw
                }
                track.contentSize = CGSize(width: track.bounds.width, height: h)
            } else {
                for (i, l) in labels.enumerated() {
                    let slot = CGRect(x: x, y: 3, width: widths[i], height: h - 6)
                    slots.append(slot); l.frame = slot; x += widths[i]
                }
                track.contentSize = CGSize(width: x + 3, height: h)
            }
            place(selected)
        }
        private func place(_ i: Int) {
            guard i < slots.count else { return }
            pill.frame = slots[i]
            for (k, l) in labels.enumerated() { l.textColor = k == i ? .label : .secondaryLabel }
        }
        @objc private func tapped(_ g: UITapGestureRecognizer) {
            let p = g.location(in: track)
            guard let i = slots.firstIndex(where: { $0.contains(p) }), i != selected else { return }
            select(i, animated: true)
            onSelect?(i)
        }
        func select(_ i: Int, animated: Bool) {
            selected = i
            guard i < slots.count else { return }
            if animated {
                UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0,
                               options: [.allowUserInteraction]) { self.place(i) }
            } else { place(i) }
            reveal(i, animated: animated)
        }
        /// The chosen word rides into view, a hundred points of the next word showing beside it.
        private func reveal(_ i: Int, animated: Bool) {
            let s = slots[i], w = track.bounds.width
            var ox = track.contentOffset.x
            if ox + w - 100 < s.maxX { ox = s.maxX - w + 100 }
            if ox > s.minX - 100 { ox = s.minX - 100 }
            ox = max(0, min(ox, track.contentSize.width - w))
            track.setContentOffset(CGPoint(x: ox, y: 0), animated: animated)
        }
    }
    func makeUIView(context: Context) -> Strip {
        let v = Strip()
        v.selected = tab.rawValue
        v.onSelect = { [coordinator = context.coordinator] i in
            if let t = MTMediaTab(rawValue: i) { coordinator.parent.tab = t }
        }
        return v
    }
    func updateUIView(_ v: Strip, context: Context) {
        context.coordinator.parent = self
        if v.selected != tab.rawValue { v.select(tab.rawValue, animated: true) }
    }
    final class Coordinator {
        var parent: MTTabStrip
        init(_ p: MTTabStrip) { parent = p }
    }
}

/// THE PANES ARE TURNED BY THE FINGER (the author's word 22.09): a swipe to the left or the right over
/// the panes moves to the next tab and back. The platform's own recogniser does it — UISwipeGestureRecognizer,
/// which fires only on a quick horizontal stroke and fails on a vertical one, so the list keeps every bit
/// of its scrolling; it takes no touch from what lies under it (cancelsTouchesInView = false), so a tap on
/// a row, a hold on a picture and the strip above go on answering as before. The recognisers are hung on
/// the page's own scroll view, the one place that sees the whole pane.
struct MTSwipePanes: UIViewRepresentable {
    let onNext: () -> Void
    let onBack: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> UIView {
        let v = UIView(frame: .zero); v.isUserInteractionEnabled = false
        return v
    }
    func updateUIView(_ v: UIView, context: Context) {
        context.coordinator.parent = self
        DispatchQueue.main.async {
            var s: UIView? = v.superview
            while let x = s, !(x is UIScrollView) { s = x.superview }
            guard let scroll = s as? UIScrollView else { return }   // SILENT-OK: the page is not laid out yet; the next pass finds it
            context.coordinator.attach(to: scroll)
        }
    }
    final class Coordinator {
        var parent: MTSwipePanes
        private weak var host: UIScrollView?
        init(_ p: MTSwipePanes) { parent = p }
        func attach(to scroll: UIScrollView) {
            guard host !== scroll else { return }
            host = scroll
            for dir in [UISwipeGestureRecognizer.Direction.left, .right] {
                let g = UISwipeGestureRecognizer(target: self, action: #selector(swipe(_:)))
                g.direction = dir
                g.cancelsTouchesInView = false   // the row under the finger keeps its own tap
                scroll.addGestureRecognizer(g)
            }
        }
        @objc private func swipe(_ g: UISwipeGestureRecognizer) {
            if g.direction == .left { parent.onNext() } else { parent.onBack() }
        }
    }
}

struct MTScrollTouchesNow: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let v = UIView(frame: .zero); v.isUserInteractionEnabled = false
        return v
    }
    func updateUIView(_ v: UIView, context: Context) {
        DispatchQueue.main.async {
            var s: UIView? = v.superview
            while let x = s, !(x is UIScrollView) { s = x.superview }
            (s as? UIScrollView)?.delaysContentTouches = false
        }
    }
}
