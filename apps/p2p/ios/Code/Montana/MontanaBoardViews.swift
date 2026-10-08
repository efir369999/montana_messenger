import SwiftUI
import UIKit.UIGestureRecognizerSubclass
import AVKit
import PhotosUI
import Photos
import QuickLook
import LinkPresentation
import UniformTypeIdentifiers

// ════════════════════════════════════════════════════════════
// THE WALL ON A PAGE (the author's word 24.09). The posts of one wall — mine (owner nil) or a correspondent's — each
// with its words, its files and, under it, its keepers, likes, comments, downloads and reposts. The platform's own
// pieces only: a grouped list's cells, the system's glyphs, the system's menu, a sheet with the cross and the check.
// No view here reads an environment object: the wall stands on pages hosted from the settings too.
// ════════════════════════════════════════════════════════════

/// WHAT THE WALL SHOWS OVER ITSELF (the critic 25.09): a post's comments, or a post's report — one sheet at a time, from the one
/// presenter (MTBoardPresenting). The new post's page is a tree of its own on the platform's own sheet (MTBoardComposer.present).
enum MTBoardSheet: Identifiable {
    case comments(String, String?)
    case report(MontanaReport, Bool)   // the report, and whether its person may be blocked with it
    var id: String {
        switch self {
        case .comments(let p, let w): return "cmt#" + (w ?? "") + "#" + p
        case .report(let r, _): return "rep#" + r.mid
        }
    }
    /// A POST REPORTED (Guideline 1.2 — the terms promise «any letter or person can be reported from its menu»): its writer
    /// when this phone knows them, and then they may be blocked with it; a writer the wall never named is reported through
    /// the wall that carried the post, and nobody is blocked for another's words.
    static func reporting(_ p: MTBoardSeen, on owner: String?) -> MTBoardSheet {
        if case .peer(let conv) = MTBoard.shared.writer(of: p, on: owner) {
            return .report(MontanaReport(peer: conv, peerName: p.byName, text: p.text, mid: p.id), true)
        }
        return .report(MontanaReport(peer: owner ?? "", peerName: p.byName, text: p.text, mid: p.id), false)
    }
}

/// THE WALL'S ONE PRESENTER (the critic 25.09): a post's comments, a report and a writer's page rise OVER
/// the list or the stack that draws the wall — never from inside one of its rows. A destination or a sheet set inside a lazy
/// container is lost when its row leaves the screen (the platform says so of navigationDestination), so every page that
/// draws a wall — a person's page, my page, the feed — wears this once, on the container itself.
struct MTBoardPresenting: ViewModifier {
    @Binding var sheet: MTBoardSheet?
    @Binding var page: MTBoardRoute?
    func body(content: Content) -> some View {
        content
            .sheet(item: $sheet) { s in
                switch s {
                case .comments(let pid, let owner):
                    // A COMMENTER'S FACE OPENS THEIR PAGE: the sheet goes down first, then the page rises where the wall stands.
                    MTBoardComments(postId: pid, owner: owner) { w in
                        sheet = nil
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { MTBoardOpen.go(w, page: $page) }
                    }
                    .montanaMotionMeter()   // every rise and fall of the wall's sheets and pages is measured (25.09)
                case .report(let r, let blocks):
                    MontanaReportSheet(report: r, onBlock: {
                        if blocks, let s = ChatStore.live, !s.isBlocked(r.peer) { s.toggleBlocked(r.peer) }
                    }, offersBlock: blocks)
                    .montanaMotionMeter()
                }
            }
            .navigationDestination(item: $page) { r in
                switch r {
                case .mine: MontanaMyProfileView().montanaMotionMeter()
                case .person(let c): MontanaPeerInfoScreen(chat: c).montanaMotionMeter()
                case .words(let r): MTLetterPage(letter: r).montanaMotionMeter()   // a folded post, whole (26.09)
                case .media(let s): MTBoardMediaPage(show: s).montanaMotionMeter()   // a post's picture and the page's, up and down (29.09)
                }
            }
    }
}

/// WHERE A WRITER'S NAME LEADS (the author's word 25.09: «it shows the page crookedly — it must show it whole; the page has one
/// owner, nothing is redrawn»): my own name leads to My page — the one «My profile» and the drawer's face open, face and all
/// (MontanaMyProfileView) — never to the room of my saved letters, which is its panes alone; a correspondent's leads to their
/// page (MontanaPeerInfoScreen).
enum MTBoardRoute: Hashable, Identifiable {
    case mine
    case person(Chat)
    case words(MTLetterRead)   // a folded post opened whole on the letter's page (26.09)
    case media(MTBoardShow)    // the page's pictures and videos, one screen each, up and down (29.09)
    var id: String {
        switch self {
        case .mine: return "me"
        case .person(let c): return "p#" + c.id
        case .words(let r): return "w#" + r.id
        case .media(let s): return "m#" + (s.owner ?? "") + "#" + s.start
        }
    }
}

/// THE ROAD FROM A WRITER'S NAME TO THEIR PAGE (the author's word 24.09: «a tap on the post's head, where the publisher's name
/// is, goes to their page»), one for the wall, the feed and the comments: mine is My page (MTBoardRoute.mine), a
/// correspondent's is theirs; a writer this phone was never told of has none.
enum MTBoardOpen {
    static func route(of w: MTBoardWriter) -> MTBoardRoute? {
        switch w {
        case .me: return .mine
        case .peer(let conv):
            let all = ChatStore.live?.listChats() ?? []
            return .person(all.first { $0.convId == conv }
                ?? Chat(name: conv, lastMessage: "", time: "", unread: 0, status: "Montana address", convId: conv))
        case .unknown: return nil
        }
    }
    static func go(_ w: MTBoardWriter, page: Binding<MTBoardRoute?>) {
        if let r = Self.route(of: w) { page.wrappedValue = r }
    }
}

struct MTBoardWriteIcon: View {
    var side: CGFloat = 44
    var body: some View {
        Image("WriteOnWall").renderingMode(.original).resizable().scaledToFit()
            .frame(width: side, height: side).accessibilityHidden(true)
    }
}

/// THE WALL'S WRITE BUTTON'S FACE, ONE DRAWING (26.09): the wall draws it as its button, the page ground's preview as the page will
/// stand -- the glyph, the words and the plate's one-tone liquid glass.
struct MTBoardWriteFace: View {
    var body: some View {
        HStack(spacing: 10) {
            MTBoardWriteIcon(side: 40)
            Text("Write on the wall")
            Spacer(minLength: 0)
        }
        .foregroundColor(.primary)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, minHeight: 50)
        .montanaOctagonFace(bar: true, height: 50)   // the plate's one-tone liquid glass, as every button of the page (the author's word 25.09)
        .contentShape(Rectangle())
    }
}

/// THE WALL'S ROWS (the critic 25.09 — the author's screenshot: a hole between the tabs and «Write on the wall»). The write
/// button, the posts on their way, the empty word or the posts — each its OWN row of the container that holds the wall. On a
/// person's page that container is the page's own list, and every post is one of its cells, measured by itself: the whole
/// wall was once ONE cell holding a lazy stack, the list took that cell's height before the stack had drawn its posts, and
/// centred the wall in a cell taller than it — on any phone, as soon as the posts drawn differed from the posts guessed. No
/// row here is a lazy container and no row presents anything: the sheets and the pages rise from the container
/// (MTBoardPresenting).
struct MTBoardRows: View {
    let owner: String?          // the wall's owner by reference; nil — my own wall
    /// The wall's side margin: its own on a page of its own (My page), none inside a list that already gives one (24.09).
    var edge: CGFloat = MTPageEdge.side
    @Binding var sheet: MTBoardSheet?
    @Binding var page: MTBoardRoute?
    @ObservedObject private var board = MTBoard.shared

    var body: some View {
        let posts = board.posts(on: owner)
        let going = board.sending(on: owner)
        if board.canWrite(on: owner) {
            Button { MTBoardComposer.present(on: owner) } label: { MTBoardWriteFace() }   // one drawing of the button (26.09)
            .buttonStyle(.plain)
            .background(MTEdgeMark("wall"))   // where the wall stands on the screen, said to the diary (24.09)
            .modifier(MTBoardRowRoom(edge: edge))
        }
        // A DRAFT STANDS ON ITS WALL (the author's word 25.09: «the wall keeps even a draft not published»): the post not yet
        // posted, as its writer left it, over the posts on their way.
        if let d = board.draft(on: owner) {
            MTBoardDraftCell(draft: d, owner: owner).modifier(MTBoardRowRoom(edge: edge))
        }
        // A POST ON ITS WAY stands at once as it will be published, under the bar of its files (the author's word
        // 24.09) — the page it was written on may be closed long before the node holds them all. Its row is its own
        // (MTBoardOutgoing.row), never the post's name: the moment the post is published its row leaves and the post's arrives.
        ForEach(going, id: \.row) { o in
            MTBoardSendingCell(o: o, owner: owner, onWriter: open).modifier(MTBoardRowRoom(edge: edge))
        }
        if posts.isEmpty && going.isEmpty && board.draft(on: owner) == nil {
            empty.modifier(MTBoardRowRoom(edge: edge))
        } else {
            ForEach(posts) { p in
                VStack(spacing: 12) {
                    MTRepostBar(postId: p.id, wall: owner)   // a repost on its way, over the post it takes (25.09)
                    MTBoardCell(post: p, owner: owner, onComments: { sheet = .comments(p.id, owner) }, onWriter: open,
                                onReport: { sheet = .reporting(p, on: owner) },
                                onOpenWords: { sheet = .comments(p.id, owner) },
                                onShow: { i in page = .media(MTBoardShow(pid: p.id, at: i, owner: owner, feed: nil)) })
                }
                .modifier(MTBoardRowRoom(edge: edge))
            }
        }
    }

    /// WHAT THE SCREEN SAYS IS WHAT THE OWNER SAID (the critic's P3): «No posts yet» only over a page the owner sent; before
    /// it, the wall is said to be on its way — only from a phone whose build carries it; with nothing to wait for, nothing.
    /// THE WALL SHOWS ON EVERY PAGE, FROM EVERY PHONE (the author's word 24.09, the second) — and a look asks nothing (the
    /// critic's P1): the owner carries the page to every correspondent whose build speaks the wall (MTBoard.pushDue), and a
    /// new version is fetched at the owner's word. Opening this page tells its owner nothing.
    private var empty: some View {
        VStack(spacing: 10) {
            if board.isAsking(owner) && !board.hasPage(owner) {
                ProgressView()
            } else if board.hasPage(owner) {
                Image(systemName: "text.below.photo").font(.system(size: 42)).foregroundColor(.gray)
                Text("No posts yet").foregroundColor(.gray).font(.subheadline)
            } else if let owner, !owner.isEmpty, board.speaks(owner) || MTPipeBook.first(for: owner) != nil {
                // A PIPE NOBODY HAS ANSWERED YET SAYS SO (25.09, T3: a page opened from a card shared in a chat — a pipe born a
                // minute ago, its owner's phone silent; the wall stood blank with no word): until the other phone answers on
                // this road nothing of theirs can come by it, and the page says whose phone it waits for.
                Image(systemName: "text.below.photo").font(.system(size: 42)).foregroundColor(.gray)
                Text("The wall comes when \(MTBoard.nameOf(owner))'s phone answers.")
                    .foregroundColor(.gray).font(.subheadline).multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity).padding(.vertical, 36)
    }
    /// THE WRITER'S PAGE (the author's word 24.09: «a tap on the post's head, where the publisher's name is, goes to their
    /// page»): mine is my own room's page, a correspondent's is theirs.
    private func open(_ w: MTBoardWriter) { MTBoardOpen.go(w, page: $page) }
}

/// A WALL'S ROW ROOM (25.09): its side margin and six points above and below — twelve between two posts, as the stack's own
/// spacing was — on a list and on a stack alike.
private struct MTBoardRowRoom: ViewModifier {
    let edge: CGFloat
    func body(content: Content) -> some View { content.padding(.horizontal, edge).padding(.vertical, 6) }
}

/// THE WALL ON A PAGE THAT SCROLLS BY ITSELF (My page, the author's word 24.09): the wall's rows in a lazy stack — a post is
/// drawn, and its pictures brought, when it comes onto the screen (25.09) — with the one presenter on the stack. A page that
/// IS a list draws the same rows as its own and wears the presenter on the list (MontanaPeerInfoScreen).
struct MTBoardPane: View {
    let owner: String?          // the wall's owner by reference; nil — my own wall
    var edge: CGFloat = MTPageEdge.side
    @State private var sheet: MTBoardSheet? = nil
    @State private var page: MTBoardRoute? = nil
    var body: some View {
        LazyVStack(spacing: 0) { MTBoardRows(owner: owner, edge: edge, sheet: $sheet, page: $page) }
            .padding(.top, 2)
            .modifier(MTBoardPresenting(sheet: $sheet, page: $page))
            .onAppear { MTBoard.shared.look(owner) }   // THE LOOK ASKS (25.09): a page of another's wall asks for it as it opens
    }
}

/// A POST BEING WRITTEN, IN ITS OWN CELL (the author's word 24.09: «the preview of the post one to one as in the
/// publication — how the track or the file will be attached, the words and so on»): its words a field in the post's own
/// font, its pictures drawn from the files the page picked, a touch on a picture opening its frame.
struct MTBoardDrafting {
    var text: Binding<String>
    var focus: FocusState<Bool>.Binding
    var sources: [URL]
    var open: Bool
    var onTile: (Int) -> Void
}

/// One post: the writer, the words, the files, and the row of its peers and marks. On its way (sending) it stands as
/// it will be published, without marks or menu yet; being written (draft), it stands as it will be published, whole —
/// its marks at nought and its menu still, the finger's only for its words and its pictures' frames.
struct MTBoardCell: View {
    let post: MTBoardSeen
    let owner: String?
    var onComments: () -> Void
    var onWriter: (MTBoardWriter) -> Void = { _ in }
    var sending = false
    var draft: MTBoardDrafting? = nil
    /// The files of a post not yet posted, drawn from this phone's own copies — a draft standing on its wall (25.09).
    var sources: [URL]? = nil
    /// Drawn on its wall's own page — the owner needs no link to the page it stands on; in the feed (25.09), off it.
    var onItsWall = true
    /// Another person's post may be reported from its menu (Guideline 1.2, 25.09): the host shows the report.
    var onReport: (() -> Void)? = nil
    /// A folded post opens whole on the letter's page (26.09): the host sets the route, the row presents nothing.
    var onOpenWords: (() -> Void)? = nil
    /// A picture or a video of a published post opens its page's viewer (MTBoardMediaPage): the host sets the route, the row presents nothing.
    var onShow: ((Int) -> Void)? = nil
    /// The post on its own page, over its comments (02.10): its words whole, no tap to open what is open.
    var whole = false
    @ObservedObject private var board = MTBoard.shared
    @ObservedObject private var fold = MTFilterFold.shared   // the filter's fold, opened for the post by the person's tap

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if let from = post.from, !from.isEmpty {
                reposted(from)
            }
            if folded {
                unfold
            } else if let draft {
                // THE WORDS WHERE THEY WILL STAND: the post's own font and colour, nothing of a field's own around them.
                TextField("Write something", text: draft.text, axis: .vertical)
                    .font(.body).foregroundColor(.primary)
                    .focused(draft.focus)
                    .disabled(!draft.open)
            } else if !post.text.isEmpty {
                // USER-DATA: the words of the post, as its writer wrote them
                MTPostText(text: post.text, onOpen: whole ? nil : onOpenWords, whole: whole)
            }
            if !folded, let raw = post.lp, let linked = MTLinkPreview.parse(raw) {
                MTWallLink(card: linked)
            }
            if !folded, !post.media.isEmpty {
                MTBoardMediaView(post: post, owner: owner, sources: draft?.sources ?? sources, onTile: draft?.onTile, inFeed: !onItsWall,
                                 onShow: sending ? nil : onShow)
            }
            if !sending { counters.allowsHitTesting(draft == nil) }
        }
        .padding(12)
        .contentShape(Rectangle())
        .onTapGesture { if draft == nil && !sending && !whole { onComments() } }
        // A POST STANDS ON THE PAGE'S GROUND IN ONE-TONE GLASS (the author's word 25.09: «the posts' bubbles on the wall the
        // other way round -- liquid glass, but ONE-TONE»): the system's regular glass in the bubble's own shape -- frosted, one
        // tone over any ground -- while the write button beside them is the clear glass.
        .background { MTBoardPostPlate() }
        // A POST ON THE SCREEN IS A POST SEEN (06.10): its wall is told once (MTBoard.view); a post being written or on its way is not.
        .onAppear { if draft == nil, !sending { board.view(post, on: owner) } }
    }

    /// THE WALL A REPOST CAME FROM IS A LINK (the author's words 25.09: «on the repost's line, the one it came from is
    /// clickable, in the system's blue», «after "Reposted from" the name must open its page»): the whole line is the target
    /// and opens that wall's page wherever this phone holds the post as itself (MTBoard.source) — on my wall, on a person's
    /// page, in the feed; the name it shows is the name this phone knows that wall by, so the word and the link agree. A
    /// phone that holds the post nowhere shows the name the repost carried, as a word.
    @ViewBuilder private func reposted(_ from: String) -> some View {
        if draft == nil, let src = board.source(of: post, on: owner) {
            Button { onWriter(src) } label: {
                HStack(spacing: 0) {
                    Label {
                        // USER-DATA: the name of the wall the post was taken from, as this phone knows that wall
                        Text("Reposted from \(Text(verbatim: Self.name(of: src, said: from)).foregroundColor(Color(uiColor: .systemBlue)))")
                    } icon: { Image(systemName: "arrow.2.squarepath") }
                    Spacer(minLength: 0)
                }
                .font(.caption).foregroundColor(.secondary)
                .frame(minHeight: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            Label { Text("Reposted from \(from)") } icon: { Image(systemName: "arrow.2.squarepath") }
                .font(.caption).foregroundColor(.secondary)
        }
    }

    /// The name the repost's line shows for a wall this phone can open: the name this phone knows it by — the link and the
    /// word it says always agree — and the name the repost carried where this phone knows none.
    private static func name(of w: MTBoardWriter, said: String) -> String {
        switch w {
        case .me: let n = E2E.myDisplayName(); return n.isEmpty ? said : n
        case .peer(let c): return MTBoard.nameOf(c)
        case .unknown: return said
        }
    }
    /// THE FILTER (Guideline 1.2 — the terms promise it for every letter, and a post is one): another person's post carrying
    /// an objectionable word stands folded, its words and its pictures, until the person's own tap; the fold is the post's
    /// (MTFilterFold), not one drawing of it. A post being written is never folded.
    private var folded: Bool {
        draft == nil && !post.mine && MontanaSafety.filterOn && !fold.opened.contains(post.id) && MontanaContentFilter.flags(post.text)
    }
    private var unfold: some View {
        Button { withAnimation(.easeOut(duration: 0.15)) { MTFilterFold.shared.open(post.id) } } label: {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Hidden by the filter", systemImage: "eye.slash").font(.callout)
                    Text("Tap to show").font(.caption).foregroundColor(.secondary)
                }
                Spacer(minLength: 0)
            }
            .foregroundColor(.primary)
            .frame(minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var header: some View {
        let w = board.writer(of: post, on: owner)
        let opens: Bool
        switch w {
        case .me: opens = owner != nil || !onItsWall   // in the feed my own post opens my page
        case .peer(let c): opens = c != owner || !onItsWall
        case .unknown: opens = false
        }
        return HStack(spacing: 10) {
            MTBoardByline(writer: w, name: post.byName, glyph: post.byGlyph, face: post.face, at: post.at,
                          onOpen: opens && draft == nil ? { onWriter(w) } : nil)
            if post.pinned {
                Image(systemName: "pin.fill").font(.caption).foregroundColor(.secondary)
            }
            if !sending {
                if draft == nil {
                    Menu { menuItems } label: { dots }
                } else {
                    dots.accessibilityHidden(true)   // the post's menu, as it will stand — still while it is written
                }
            }
        }
    }
    private var dots: some View {
        Image(systemName: "ellipsis").font(.system(size: 17, weight: .semibold)).foregroundColor(.secondary)
            .frame(width: 44, height: 44).contentShape(Rectangle())
    }

    @ViewBuilder private var menuItems: some View {
        // THE POST'S SHORT LINK (the author's word 02.10): it opens the post inside Montana.
        Button { MTPostLinkItem.present(post, on: owner) } label: {
            Label("Share", systemImage: "square.and.arrow.up")
        }
        if owner == nil {
            if post.pinned {
                Button { board.pin(post) } label: { Label("Unpin", systemImage: "pin.slash") }
            } else {
                Button { board.pin(post) } label: { Label("Pin", systemImage: "pin") }
            }
        }
        // MY OWN WORDS ARE MINE TO CHANGE (the author's word 30.09): my post on my own wall, never a repost.
        if owner == nil, post.mine, post.from == nil {
            Button { MTBoardEditor.present(post) } label: { Label("Edit", systemImage: "pencil") }
        }
        if post.kept {
            if !post.mine || owner == nil {
                Button { board.unkeep(post, on: owner) } label: { Label("Remove from saved", systemImage: "tray.and.arrow.up") }
            }
        } else {
            Button { Task { await board.keep(post, on: owner) } } label: { Label("Save", systemImage: "tray.and.arrow.down") }
        }
        if let owner, !post.reposted, !post.mine {
            Button { Task { await board.repost(post, from: owner) } } label: { Label("Repost", systemImage: "arrow.2.squarepath") }
        }
        if !post.text.isEmpty {
            Button { UIPasteboard.general.string = post.text } label: { Label("Copy", systemImage: "doc.on.doc") }
        }
        if let onReport, !post.mine {
            Button(role: .destructive) { onReport() } label: { Label("Report", systemImage: "exclamationmark.bubble") }
        }
        // ONLY THE WALL'S OWNER DELETES A POST ON IT (the author's word 24.09): my own page, every post on it; another's
        // page, none — my own post there included.
        if owner == nil {
            Button(role: .destructive) { board.remove(post, on: owner) } label: { Label("Delete", systemImage: "trash") }
        }
    }

    /// THE POST'S PEERS AND MARKS (the author's word 24.09): keepers, likes, comments, reposts — each a mark that
    /// answers the finger — and the downloads, a count.
    private var counters: some View {
        HStack(spacing: 0) {
            mark(post.liked ? "heart.fill" : "heart", post.likes, tint: post.liked ? .red : .secondary, label: "Like") {
                board.like(post, on: owner)
            }
            // A REPOST'S COMMENTS ARE ITS ORIGINAL'S (the author's word 25.09): the count of the one thread (MTBoard.thread).
            mark("bubble.left", board.thread(of: post, on: owner)?.post.commentCount ?? 0, label: "Comments") { onComments() }
            mark(post.kept ? "tray.full.fill" : "tray.and.arrow.down", post.keepers, tint: post.kept ? .accentColor : .secondary, label: "Keepers") {
                if post.kept { board.unkeep(post, on: owner) } else { Task { await board.keep(post, on: owner) } }
            }
            mark("arrow.2.squarepath", post.reposts, tint: post.reposted ? .accentColor : .secondary, label: "Repost") {
                if let owner, !post.reposted, !post.mine { Task { await board.repost(post, from: owner) } }
            }
            Spacer(minLength: 0)
            // THE EYE IN THE CORNER (the author's words 06.10.2026 00:3x MSK: «under the posts, bottom right, an eye and how many
            // views»): how many people saw the post, by its wall owner's count, in the platform's short form past a thousand; a wall
            // whose owner's build counts none shows no eye rather than a zero nobody counted.
            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.down.circle")
                    // USER-DATA: a count, digits only
                    Text(verbatim: String(post.downloads))
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Text("Downloads"))
                if let seen = post.views {
                    HStack(spacing: 4) {
                        Image(systemName: "eye")
                        // USER-DATA: a count, digits only
                        Text(verbatim: seen.formatted(.number.notation(.compactName))).lineLimit(1)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text("Views"))
                    // USER-DATA: a count, digits only
                    .accessibilityValue(Text(verbatim: String(seen)))
                }
            }
            .font(.footnote.weight(.semibold)).foregroundColor(.secondary)
            .lineLimit(1)
            .fixedSize()
        }
    }
    private func mark(_ glyph: String, _ n: Int, tint: Color = .secondary, label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: glyph)
                // USER-DATA: a count, digits only
                Text(verbatim: String(n))
            }
            .font(.footnote.weight(.semibold))
            .foregroundColor(tint)
            .frame(minWidth: 48, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
    }
}

/// The files of a post: pictures and videos as tiles, each in its own frame (MTBoardMosaic), tracks and files as rows.
/// A touch fetches the file from the node's store (once) and opens it where the platform opens such a thing. A post
/// being written draws its pictures from the files its page picked, and a touch on one opens its frame instead.
/// A link the post already opened. The writer read the page; the picture rides in the post.
/// A tap opens the address, which is how a video or a track starts. A visitor draws these bytes
/// and does not open the page until that tap.
struct MTWallLink: View {
    let card: MTLinkPreview
    @State private var image: UIImage?
    @State private var sound = false
    @State private var media: URL?

    var body: some View {
        Group {
            if kind == nil {
                Button { open() } label: { face }.buttonStyle(.plain)
            } else {
                face.onTapGesture { press() }
            }
        }
        .accessibilityLabel(Text(LocalizedStringKey(mark)))
        .accessibilityValue(Text(verbatim: card.t ?? card.u)) // USER-DATA: the page title its writer read
        .task(id: card.u) { await prepare() }
        .task(id: card.i) { image = await MTBoardPoster.decoded(card.i) }
    }

    private var mark: String {
        if kind == "aud" { return "Music" }
        if kind == "vid" { return "Video" }
        return "Link"
    }

    private var kind: String? {
        guard let u = URL(string: card.u) else { return nil }
        return MTLinkPreviewBuilder.playKind(u)
    }

    private var ratio: CGFloat {
        let w = CGFloat(card.w ?? 16)
        let h = CGFloat(max(card.h ?? 9, 1))
        return min(2, max(0.75, w / h))
    }

    @ViewBuilder private var face: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let image {
                Color.clear
                    .aspectRatio(ratio, contentMode: .fit)
                    .overlay {
                        Image(uiImage: image).resizable().scaledToFill()
                        if let media {
                            MontanaClipPlayer(url: media, active: true, paused: false, onProgress: { _ in }, muted: !sound, quiet: true)
                                .allowsHitTesting(false)
                        } else if kind != nil {
                            Image(systemName: kind == "aud" ? "music.note.circle.fill" : "play.circle.fill")
                                .font(.system(size: 44))
                                .foregroundStyle(.white)
                        }
                        if sound {
                            Image(systemName: "speaker.wave.2.fill")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(8)
                                .background(.black.opacity(0.45), in: Circle())
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                                .padding(8)
                                .allowsHitTesting(false)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            if let site = card.s, site.isEmpty == false {
                Text(verbatim: site).font(.caption).foregroundColor(.secondary).lineLimit(1) // USER-DATA: the site name the card carries
            }
            if let title = card.t, title.isEmpty == false {
                Text(verbatim: title).font(.subheadline.weight(.semibold)).foregroundColor(.primary).lineLimit(2) // USER-DATA: the page title the card carries
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func prepare() async {
        guard let u = URL(string: card.u), kind != nil else { return }
        // A SERVICE'S PAGE PLAYS IN THAT SERVICE (App Review 5.2.2 and 5.2.3, 08.10.2026): its stream is the service's to serve,
        // never ours to draw -- the card shows its picture, and a tap opens the link there. Only a media file itself plays in place.
        guard ["mp4", "mov", "m4v", "webm", "mp3", "m4a", "aac", "wav", "flac"].contains(u.pathExtension.lowercased()) else { return }
        media = u
    }
    private func press() {
        guard let media else { open(); return }
        if !sound {
            sound = true
        } else {
            sound = false
            VideoPresenter.present(remote: media)
        }
    }
    private func open() {
        guard let u = URL(string: card.u) else { return }
        MontanaP2PTrace.mark("post_link", "open " + (kind ?? "page"))
        UIApplication.shared.open(u)
    }
}

struct MTBoardMediaView: View {
    let post: MTBoardSeen
    let owner: String?
    var sources: [URL]? = nil
    var onTile: ((Int) -> Void)? = nil
    /// The post stands in the feed: the feed's tracks are the queue; on its wall, the wall's (MTBoardPlaylist, 29.09).
    var inFeed = false
    /// A picture or a video of a published post opens the viewer of its page (MTBoardMediaPage, 29.09); nil -- where it stands alone.
    var onShow: ((Int) -> Void)? = nil
    @ObservedObject private var board = MTBoard.shared
    @ObservedObject private var now = MTNowPlaying.shared
    @State private var looked = 0   // a picture brought to be seen redraws its tile

    var body: some View {
        let visual = post.media.indices.filter { Self.visual(post.media[$0]) }
        let other = post.media.indices.filter { !Self.visual(post.media[$0]) }
        VStack(spacing: 8) {
            if !visual.isEmpty {
                MTBoardMosaic(shapes: visual.map { Self.shape(of: post.media[$0]) }) {
                    ForEach(visual, id: \.self) { i in tile(i) }
                }
            }
            ForEach(other, id: \.self) { i in row(i).allowsHitTesting(onTile == nil) }
        }
    }

    static func visual(_ m: MTBoardMedia) -> Bool { m.kind == "img" || m.kind == "vid" }
    /// A picture's shape in its post: the frame its writer gave it; a post from before the frame, its poster's own —
    /// held to the shapes a post takes.
    static func shape(of m: MTBoardMedia) -> CGFloat {
        if let f = m.fr { return CGFloat(MTBoardFrame.held(f.a)) }
        if let s = MTBoardPoster.shape(m.thumb) { return CGFloat(MTBoardFrame.held(Double(s))) }   // its header alone (25.09)
        return 1
    }
    /// A picture's file on this phone, when it is here: the page's pick, or the post's own file in the media store — the
    /// writer's, a keeper's, one a touch brought.
    private func local(_ i: Int) -> URL? {
        if let sources { return i < sources.count ? sources[i] : nil }
        let name = MTBoard.fileName(post.id, i, post.media[i].ext)
        if MontanaMediaStore.exists(name) { return MontanaMediaStore.url(name) }
        _ = looked
        return MTBoardLook.here(post.id, i, post.media[i].ext)   // a picture brought to be seen (25.09)
    }
    /// A PICTURE OF ANOTHER'S WALL IS BROUGHT TO BE SEEN (the author's word 25.09: «the media on a page are blurred»): a
    /// tile with no file here brings the picture silently (MTBoardLook) and redraws at its own pixels; a video stays its
    /// poster until a touch.
    private func look(_ i: Int) async {
        guard sources == nil, i < post.media.count, local(i) == nil else { return }
        if await MTBoardLook.bring(post.media[i], pid: post.id, i: i) != nil { looked += 1 }
    }

    private func tile(_ i: Int) -> some View {
        let m = post.media[i]
        return Button { if let onTile { onTile(i) } else if let onShow, sources == nil { onShow(i) } else { open(i) } } label: {
            ZStack {
                if m.kind == "vid", sources == nil {
                    MTBoardClip(media: m, local: local(i), source: MTBoard.streamSource(post, i))   // a video plays by itself (25.09)
                } else {
                    MTBoardPicture(media: m, source: local(i))
                    if m.kind == "vid" {
                        Image(systemName: "play.circle.fill").font(.system(size: 30)).foregroundColor(.white.opacity(0.9))
                    }
                }
                if board.fetching.contains(post.id) { ProgressView() }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(LocalizedStringKey(m.kind == "vid" ? "Video" : "Photo")))
        .task(id: post.id + "#" + String(i)) { await look(i) }
    }

    @ViewBuilder private func row(_ i: Int) -> some View {
        if post.media[i].kind == "aud" { track(i) } else { fileRow(i) }
    }

    /// A TRACK OF A POST IS A TRACK OF THE ONE PLAYER (the author's word 24.09: «the music with one owner, as in the
    /// player, switched on and looking in our style»): the playing track wears the mini player itself (MontanaPlayerBar,
    /// row) and every other stands in the mini's face — its play, its name in the plate, its length — as the music
    /// page's rows do. The whole row is one target: a touch brings the track once from the node and plays it through
    /// VoicePlayer, the page's tracks as the queue (MTBoardPlaylist, 29.09).
    @ViewBuilder private func track(_ i: Int) -> some View {
        let m = post.media[i]
        if now.file == MTBoard.fileName(post.id, i, m.ext) {
            MontanaPlayerBar(row: true).padding(.horizontal, -16)
        } else {
            Button { open(i) } label: {
                MTMiniFace(paused: true, title: (m.name as NSString).deletingPathExtension, runs: false, live: 0,
                           side: { _ in 0 < (m.dur ?? 0) ? fmtDuration(m.dur ?? 0) : "" },
                           onPlay: {}, onSeek: { _ in }, onSide: {}, onOpen: {},
                           busy: board.fetching.contains(post.id))
                    .allowsHitTesting(false)
                    .padding(.horizontal, -16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func fileRow(_ i: Int) -> some View {
        let m = post.media[i]
        let shown = (m.name as NSString).deletingPathExtension
        return Button { open(i) } label: {
            HStack(spacing: 12) {
                Image(systemName: m.kind == "aud" ? "music.note" : "doc")
                    .font(.system(size: 17, weight: .semibold)).foregroundColor(.secondary)
                    .frame(width: 36, height: 36)
                    .background(Color(white: 0.16), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    // USER-DATA: the track's or the file's own name
                    Text(verbatim: shown.isEmpty ? m.name : shown).foregroundColor(.primary).lineLimit(1)
                    Text(mtSize(m.size)).font(.caption).foregroundColor(.secondary)
                }
                Spacer(minLength: 0)
                if board.fetching.contains(post.id) { ProgressView() }
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func open(_ i: Int) {
        let m = post.media[i]
        let p = post, wall = owner
        // The poster stands at once, so the tap never waits for the file.
        if m.kind == "img", sources == nil {
            let among = MTBoard.pictures(p), mine = MTBoard.fileName(p.id, i, m.ext)
            if among.contains(where: { x in x.id == mine }) { PhotoPresenter.present(mine, among: among); return }
            Task { @MainActor in
                var now = MTBoardPoster.kept(m.thumb)
                if now == nil { now = await MTBoardPoster.decoded(m.thumb) }
                PhotoPresenter.present(now: now) {
                    guard let f = await MTBoard.shared.file(p, i, on: wall) else { return nil }
                    let u = MontanaMediaStore.url(f)
                    return await Task.detached(priority: .userInitiated) { MTBoardImage.upright(u, kind: "img", longest: 2400) }.value
                }
            }
            return
        }
        // A VIDEO PLAYS FROM ITS FIRST PIECES (the author's word 25.09): the full player opens on the loader at once, with
        // sound; the file, whole, is kept as a touch's copy (file — this phone becomes the post's peer, the download counted).
        if m.kind == "vid", sources == nil, local(i) == nil, let s = MTBoard.streamSource(p, i) {
            VideoPresenter.present(stream: s) { Task { _ = await MTBoard.shared.file(p, i, on: wall) } }
            return
        }
        // A TRACK PLAYS FROM ITS FIRST PIECES (the author's word 25.09): the one player plays it at once through its loader;
        // a track whole is kept as a touch's copy. THE PAGE IS THE PLAYLIST (the author's word 29.09 on 2002): the queue is
        // every track of the page the post stands on -- the feed's in the feed, the wall's on the wall -- so the bar's track
        // buttons and a track's end walk the whole page, not the post's neighbours; a post not yet on its page (on its way)
        // plays its own.
        if m.kind == "aud", sources == nil {
            let key = MTBoard.fileName(p.id, i, m.ext)
            let page: [(post: MTBoardSeen, wall: String?)] = inFeed
                ? board.feed().map { (post: $0.post, wall: $0.owner) }
                : board.posts(on: wall).map { (post: $0, wall: wall) }
            var tracks = MTBoardPlaylist.tracks(page)
            if !tracks.contains(where: { $0.file == key }) { tracks = MTBoardPlaylist.tracks([(post: p, wall: wall)]) }
            guard let k = tracks.firstIndex(where: { $0.file == key }) else { return }
            MontanaP2PTrace.mark("music", "board queue n=\(tracks.count) at=\(k + 1) in=\(inFeed ? "feed" : "wall")")
            let player = VoicePlayer.shared
            player.queue = tracks
            player.play(index: k)
            return
        }
        Task {
            guard let f = await MTBoard.shared.file(p, i, on: wall) else { return }
            await MainActor.run {
                switch m.kind {
                case "img": PhotoPresenter.present(f, among: MTBoard.pictures(p))
                case "vid": VideoPresenter.present(f)
                case "aud":
                    // The one player plays it, the post's tracks already on this phone as the queue, in their order.
                    let tracks: [MusicTrack] = p.media.indices.compactMap { j in
                        let mj = p.media[j]
                        let fj = MTBoard.fileName(p.id, j, mj.ext)
                        guard mj.kind == "aud", MontanaMediaStore.exists(fj) else { return nil }
                        return MusicTrack(file: fj, title: mj.name, msgId: p.id, chat: wall ?? "", chatTitle: p.byName, inPost: true)
                    }
                    guard let k = tracks.firstIndex(where: { $0.file == f }) else { return }
                    let player = VoicePlayer.shared
                    player.queue = tracks
                    player.play(index: k)
                default: MTBoardDocPresenter.present(f, name: m.name)
                }
            }
        }
    }
}

/// THE PAGE IS THE PLAYLIST (the author's word 29.09 on 2002: «on the wall and in the feed it must build the playlist by the feed or
/// the page, and skip; in the feed it saw only the neighbouring tracks, on the wall too»): the one rule of the posts' tracks as the
/// one player's queue -- every track of the given posts in their order, each once by its file (a post standing on two walls of the
/// feed is one post); a track on this phone from the disk, another on its own loader from its pieces (MTBoard.streamSource), kept
/// whole as a touch's copy once it plays; a track with neither stands out of the queue. WHERE A TRACK LIES IS NEVER SAID (the
/// author's word 29.09 ~23:20: «take the addresses out of the tracks everywhere»): a post's track is marked as one
/// (MusicTrack.inPost -- it has no letter to go to), and no words of the feed or the wall are born for it; the post's day is the
/// track's.
@MainActor enum MTBoardPlaylist {
    static func tracks(_ posts: [(post: MTBoardSeen, wall: String?)]) -> [MusicTrack] {
        var once = Set<String>()
        var out: [MusicTrack] = []
        for (p, wall) in posts {
            for j in p.media.indices where p.media[j].kind == "aud" {
                let mj = p.media[j]
                let fj = MTBoard.fileName(p.id, j, mj.ext)
                guard once.insert(fj).inserted else { continue }
                var t = MusicTrack(file: fj, title: mj.name, msgId: p.id, chat: wall ?? "", chatTitle: p.byName, at: p.at, inPost: true)
                if !MontanaMediaStore.exists(fj) {
                    guard let sj = MTBoard.streamSource(p, j) else { continue }
                    t.stream = sj
                    t.whole = { Task { _ = await MTBoard.shared.file(p, j, on: wall) } }
                }
                out.append(t)
            }
        }
        return out
    }
}

/// THE PICTURES OF A POST, EACH IN ITS OWN SHAPE (the author's word 24.09: «the size of the photo in the post»): an odd
/// one first across the whole width, then two by two, each pair one row tall — every picture keeps the shape its writer
/// gave it, and every row fills the width. The same layout on the page that writes the post, on its way, and on the wall.
struct MTBoardMosaic: Layout {
    let shapes: [CGFloat]   // width over height, one per picture, in the post's order
    var gap: CGFloat = 4

    static func rows(_ n: Int) -> [[Int]] {
        var out: [[Int]] = []
        var i = 0
        if n % 2 == 1 { out.append([0]); i = 1 }
        while i + 1 < n { out.append([i, i + 1]); i += 2 }
        return out
    }
    private func frames(_ width: CGFloat) -> [CGRect] {
        var out = Array(repeating: CGRect.zero, count: shapes.count)
        var y: CGFloat = 0
        for row in Self.rows(shapes.count) {
            let sum = row.reduce(CGFloat(0)) { $0 + max(0.1, shapes[$1]) }
            let h = ((width - gap * CGFloat(row.count - 1)) / sum).rounded(.down)
            var x: CGFloat = 0
            for (k, i) in row.enumerated() {
                let w = k == row.count - 1 ? width - x : (h * max(0.1, shapes[i])).rounded()
                out[i] = CGRect(x: x, y: y, width: max(1, w), height: max(1, h))
                x += w + gap
            }
            y += h + gap
        }
        return out
    }
    private func width(_ p: ProposedViewSize) -> CGFloat {
        guard let w = p.width, w.isFinite, 1 < w else { return 320 }
        return w
    }
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let w = width(proposal)
        return CGSize(width: w, height: frames(w).map { $0.maxY }.max() ?? 0)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let fs = frames(bounds.width)
        for (i, s) in subviews.enumerated() where i < fs.count {
            let f = fs[i]
            s.place(at: CGPoint(x: bounds.minX + f.minX, y: bounds.minY + f.minY),
                    proposal: ProposedViewSize(width: f.width, height: f.height))
        }
    }
}

/// A POST'S PICTURE, AS SHARP AS THIS PHONE CAN DRAW IT (the author's word 24.09: «the post's picture is blurred after
/// it is published» — the poster alone stood here, 240 pixels stretched over a whole row): the file itself when it lies
/// on this phone — the writer's, a keeper's, one a touch brought — cut to the post's frame and decoded at the tile's
/// own pixels by the system's thumbnailer, off the main thread; before it, the poster the post carries, cut to the same
/// frame; before that, the tile's grey.
struct MTBoardPicture: View {
    let media: MTBoardMedia
    let source: URL?
    @Environment(\.displayScale) private var scale
    @State private var drawn: (key: String, image: UIImage)? = nil
    @State private var poster: UIImage? = nil   // the post's poster, decoded off the main thread (MTBoardPoster, 25.09)

    var body: some View {
        GeometryReader { g in
            let key = Self.key(source, media, g.size, scale)
            let sharp = (drawn?.key == key ? drawn?.image : nil) ?? (key.isEmpty ? nil : Self.cache.object(forKey: key as NSString))
            let img = sharp ?? poster ?? MTBoardPoster.kept(media.thumb)
            ZStack {
                Color(white: 0.16)
                if let img {
                    Image(uiImage: img).resizable().interpolation(.high).scaledToFill()
                        .frame(width: g.size.width, height: g.size.height).clipped()
                }
            }
            .frame(width: g.size.width, height: g.size.height)
            .task(id: key) { await draw(key, g.size) }
            .task(id: media.thumb?.count ?? 0) { if poster == nil, sharp == nil { poster = await MTBoardPoster.decoded(media.thumb) } }
        }
    }

    /// WHAT WAS DRAWN SHARP STAYS DRAWN (the author's word 25.09: «cache everything properly, at once»): a page of pictures
    /// at their own pixels, so a post scrolled back to is sharp on its first frame.
    /// A THIRD OF WHAT IT WAS, AND GONE AT THE DOOR (the critic 25.09): 160 MB let a phone leave the screen at 300–420 MB and be
    /// ended first; 48 MB draws a page of pictures sharp, and MontanaCaches empties it when the screen is left.
    private static let cache: NSCache<NSString, UIImage> = MontanaCaches.kept("wall-pictures", cost: 48_000_000)
    private static func key(_ source: URL?, _ m: MTBoardMedia, _ size: CGSize, _ scale: CGFloat) -> String {
        guard let source, 1 <= size.width, 1 <= size.height else { return "" }
        let f = m.fr.map { String(format: "%.4f,%.4f,%.4f,%.4f", $0.x, $0.y, $0.w, $0.h) } ?? "whole"
        return source.path + "#" + f + "#" + String(Int(size.width * scale)) + "x" + String(Int(size.height * scale))
    }
    private func draw(_ key: String, _ size: CGSize) async {
        guard !key.isEmpty, let source else { return }
        if let c = Self.cache.object(forKey: key as NSString) { drawn = (key, c); return }
        let px = CGSize(width: size.width * scale, height: size.height * scale)
        let kind = media.kind, frame = media.fr
        guard let img = await Task.detached(priority: .userInitiated, operation: {
            MTBoardImage.drawn(source, kind: kind, frame: frame, pixels: px)
        }).value else { return }
        Self.cache.setObject(img, forKey: key as NSString, cost: Int(img.size.width * img.size.height * 4))
        drawn = (key, img)
    }
}

/// A VIDEO IN A POST PLAYS BY ITSELF (the author's word 25.09: «a video in the feed shows playing at once, without a tap»):
/// the tile is the system player's layer — without sound, round and round — from the moment the tile stands on the screen
/// to the moment it leaves; the pieces come as the player asks for them (MTStreams), never the whole file ahead, and a file
/// this phone holds plays from the disk. Under the first frame, and wherever playing is refused, the poster stands as
/// before. A tap is the full player with sound (MTBoardMediaView.open). Where the person keeps this connection for a tap
/// (the automatic download is off for it), the tile stays its poster with the play glyph.
struct MTBoardClip: View {
    let media: MTBoardMedia
    let local: URL?
    let source: MTStreamSource?
    @State private var asset: AVURLAsset?
    @State private var shown = false
    @Environment(\.mtPaneLive) private var live

    init(media: MTBoardMedia, local: URL?, source: MTStreamSource?) {
        self.media = media
        self.local = local
        self.source = source
        // One asset for the tile's life: the loader behind it is the file's own, shared with the full player (MTStreams) —
        // born only where the tile may play (the person's rule for this connection), so a tile that will not play opens nothing.
        let plays = local == nil && MontanaNet.shared.autoDownloadAllowed
        _asset = State(initialValue: plays ? source.map { MTStreams.asset($0) } : nil)
    }

    var body: some View {
        ZStack {
            MTBoardPicture(media: media, source: local)
            if let url = playURL, local != nil || asset != nil {
                MontanaClipPlayer(url: url, active: shown && live, paused: false, onProgress: { _ in },
                                  asset: local == nil ? asset : nil, muted: true)
            } else {
                Image(systemName: "play.circle.fill").font(.system(size: 30)).foregroundColor(.white.opacity(0.9))
            }
        }
        .onAppear { shown = true }
        .onDisappear { shown = false }
    }
    private var playURL: URL? {
        if let local { return local }
        guard let source, MontanaNet.shared.autoDownloadAllowed else { return nil }
        return source.url
    }
}

/// THE HEAD OF A POST (the author's word 24.09: «show the publisher's avatar in the post too; a tap on the post's
/// head, where the publisher's name is, goes to their page»): the writer's face and name, and when — one target over its
/// whole room, when there is a page to open.
struct MTBoardByline: View {
    let writer: MTBoardWriter
    let name: String
    let glyph: String
    var face: String? = nil
    var at: Double? = nil
    var onOpen: (() -> Void)? = nil
    var body: some View {
        if let onOpen {
            Button(action: onOpen) { content }.buttonStyle(.plain)
        } else {
            content
        }
    }
    private var content: some View {
        HStack(spacing: 10) {
            MTBoardFace(writer: writer, name: name, glyph: glyph, face: face, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                // USER-DATA: the writer's name
                HStack(spacing: 6) {
                    Text(verbatim: name).font(.subheadline.weight(.semibold)).foregroundColor(.primary).lineLimit(1)
                }
                if let at {
                    Text(Date(timeIntervalSince1970: at), format: .dateTime.day().month().hour().minute())
                        .font(.caption).foregroundColor(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}

/// The writer's face: mine, the face this phone holds for a correspondent, or — for a writer it was never told of —
/// the small face the post carries; the letter or glyph when there is none. The rows' own hexagon and rim.
struct MTBoardFace: View {
    let writer: MTBoardWriter
    let name: String
    let glyph: String
    var face: String? = nil
    let size: CGFloat
    var body: some View {
        Group {
            switch writer {
            case .me:
                MTSelfFace(size: size, initial: glyph)
            case .peer(let conv):
                // The face this phone holds for them; none held, the small face the post carries (25.09).
                let file = MTNameBook.displayedPhoto(conv)
                AvatarCircle(photoURL: file, color: .black, initial: MTNameBook.face(conv, title: name), size: size,
                             image: file == nil ? Self.picture(face) : nil)
            case .unknown:
                AvatarCircle(photoURL: nil, color: .black, initial: glyph, size: size, image: Self.picture(face))
            }
        }
        .overlay(MontanaHexagon().stroke(Color.white.opacity(0.45), lineWidth: 1))
    }
    private static let pictures: NSCache<NSString, UIImage> = MontanaCaches.kept("wall-faces")
    static func picture(_ b64: String?) -> UIImage? {
        guard let b64, !b64.isEmpty else { return nil }
        let key = String(b64.hashValue) as NSString
        if let img = pictures.object(forKey: key) { return img }
        guard let d = Data(base64Encoded: b64), let img = UIImage(data: d) else { return nil }
        pictures.setObject(img, forKey: key)
        return img
    }
}

/// THE POST ON ITS WAY (the author's word 24.09: «the system's progress bar at the top of the new post's page, natively,
/// as the backup to iCloud does it — the blue line with the percentage and the data, beautifully, in liquid glass»): the
/// platform's own bar left untinted, so its blue is the system's; the share and the bytes THE NODE HAS CONFIRMED; the
/// plate's glass — the system's where it has it, the thin material with the rim before. A post whose files the node did
/// not take says so, with its try-again and, on the wall, its removal.
struct MTBoardProgress: View {
    let o: MTBoardOutgoing
    var onRetry: (() -> Void)? = nil
    var onDiscard: (() -> Void)? = nil
    var body: some View {
        let pct = Int((o.share * 100).rounded(.down))
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(o.failed ? "Could not post" : "Publishing")
                    .font(.subheadline.weight(.semibold)).foregroundColor(.primary).lineLimit(1)
                Spacer(minLength: 6)
                Text("\(pct)% · \(mtSize(o.done)) of \(mtSize(o.total))")
                    .font(.subheadline).monospacedDigit().foregroundColor(.secondary).lineLimit(1)
                if o.failed, let onRetry {
                    Button(action: onRetry) {
                        Image(systemName: "arrow.clockwise").font(.system(size: 17, weight: .semibold)).foregroundColor(.primary)
                            .frame(width: 44, height: 44).contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(Text("Try again"))
                }
                if o.failed, let onDiscard {
                    Button(action: onDiscard) {
                        Image(systemName: "trash").font(.system(size: 17, weight: .semibold)).foregroundColor(.primary)
                            .frame(width: 44, height: 44).contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(Text("Delete"))
                }
            }
            ProgressView(value: o.share)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .montanaFieldGlass(maxCut: 18)
    }
}

/// A POST ON ITS WAY, ON ITS WALL (the author's word 24.09: «the new post shows at once as it will be published»): the
/// bar of its files over the post as it will stand; a post the node did not take keeps its try-again and its removal.
struct MTBoardSendingCell: View {
    let o: MTBoardOutgoing
    let owner: String?
    var onWriter: (MTBoardWriter) -> Void = { _ in }
    var body: some View {
        VStack(spacing: 8) {
            MTBoardProgress(o: o, onRetry: { let pid = o.id; Task { _ = await MTBoard.shared.publish(pid) } },
                            onDiscard: { MTBoard.shared.discard(o.id) })
            MTBoardCell(post: o.post, owner: owner, onComments: {}, onWriter: onWriter, sending: true)
        }
    }
}

/// A POST NOT YET PUBLISHED, ON ITS WALL (the author's word 25.09: «the wall keeps even a draft not published — against failures
/// and other turns»): the post as it will stand, under a plate that names it a draft; a touch on the plate or on the post opens
/// the page that writes it, where it was left; the plate's trash throws the draft away, its files with it.
struct MTBoardDraftCell: View {
    let draft: MTBoardDraft
    let owner: String?
    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Button { MTBoardComposer.present(on: owner) } label: {
                    HStack(spacing: 8) {
                        MTBoardWriteIcon(side: 36)
                        Text("Draft").lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .font(.subheadline.weight(.semibold)).foregroundColor(.primary)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Button { MTBoard.shared.dropDraft(on: owner, why: "trash") } label: {
                    Image(systemName: "trash").font(.system(size: 17, weight: .semibold)).foregroundColor(.primary)
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(Text("Delete"))
            }
            .padding(.horizontal, 16).padding(.vertical, 4)
            .montanaFieldGlass(maxCut: 18)
            // The whole post is the button: nothing inside it answers by itself (its writer's name, its tiles, its rows).
            Button { MTBoardComposer.present(on: owner) } label: {
                MTBoardCell(post: draft.seen(on: owner), owner: owner, onComments: {}, sending: true, sources: draft.files.map { $0.url })
                    .allowsHitTesting(false)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}

/// A file of a post in the platform's own viewer (QuickLook), from wherever the wall stands.
enum MTBoardDocPresenter {
    private final class Source: NSObject, QLPreviewControllerDataSource {
        let url: URL
        init(url: URL) { self.url = url }
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem { url as NSURL }
    }
    private static var held: Source?
    static func present(_ file: String, name: String) {
        let s = Source(url: attachmentURL(file))
        held = s
        let c = QLPreviewController()
        c.dataSource = s
        MTTop.present(c, kind: "doc")   // the one door of every modal (25.09)
    }
}

/// A NEW POST (the author's word 24.09): the words, pictures and videos from the library, tracks and files from the
/// files — the platform's own pickers, the cross to leave and the check to post. THE PAGE SHOWS THE POST ONE TO ONE AS
/// IT WILL BE PUBLISHED (the author's word 24.09, the third: «the preview of how the post itself will look, one to one
/// as in the publication — how the track or the file will be attached, the words and so on»): the post's own cell — the
/// very view the wall draws, at the wall's own width — its words a field in the post's own font, its pictures drawn
/// sharp from the files picked, each in the frame its writer sets with a touch (its shape and the part it shows,
/// MTFrameCropView); under it the pickers and the files, each with its cross. The check lays the files on the node under
/// the platform's own bar at the page's head (MTBoardProgress), and the page closes when the words have gone to the
/// wall's owner; closed earlier, the post goes on — it stands on its wall under the same bar until it is out.
/// THE PAGE IS THE WALL'S DRAFT (the author's word 25.09: «drafts are permanent — nothing is reset, even after a leave to
/// another app; the wall keeps a draft not published, against failures, the network and every other turn»): every word
/// typed and every file picked is laid into the wall's store at once (MTBoard.lay), the files in the wall's own folder;
/// the page opens as it was left — after a leave, a death of the run, a restart — and the cross keeps the draft, which
/// stands on its wall (MTBoardDraftCell) until it is posted or thrown away there.
struct MTBoardComposer: View {
    let owner: String?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.montanaClose) private var montanaClose
    @ObservedObject private var board = MTBoard.shared
    @State private var text: String
    @State private var picks: [PhotosPickerItem] = []
    @State private var files: [MTBoardDraftFile]
    @State private var importing = false
    @State private var taking = 0   // the picks still on their way from the library (06.10)
    @State private var sending: String? = nil   // the post this page sent on its way ("" while it is being taken)
    @State private var failed = false
    @State private var closed = false
    @State private var framing: Framing? = nil  // the picture whose frame is being set
    @State private var at: Double
    @State private var linkCard: MTLinkPreview?
    @State private var linkURL: String
    @State private var linkGen: Int
    /// THE POST'S FIELD TAKES THE KEYS AT THE PAGE'S OPENING (24.09, the author's word: «the post's field on T3's wall was
    /// not clickable the first time»): as the business card's page does, and as the platform's own «new message» pages
    /// do — nothing to tap before writing; a tap anywhere on the post gives the field the keys again.
    @FocusState private var textFocused: Bool

    /// THE PAGE OPENS AS IT WAS LEFT (25.09): the wall's draft — its words, its files and the moment it was begun.
    init(owner: String?) {
        self.owner = owner
        let d = MTBoard.shared.draft(on: owner)
        _text = State(initialValue: d?.text ?? "")
        _files = State(initialValue: d?.files ?? [])
        _at = State(initialValue: d?.at ?? Date().timeIntervalSince1970)
        let held = MTLinkPreview.parse(d?.lp)
        let first = MTLinkPreviewBuilder.firstWebURL(in: d?.text ?? "")?.absoluteString
        _linkCard = State(initialValue: held?.u == first ? held : nil)
        _linkURL = State(initialValue: held?.u == first ? (first ?? "") : "")
        _linkGen = State(initialValue: 0)
    }

    struct Framing: Identifiable { let id: String; let image: UIImage; let frame: MTBoardFrame }

    private var empty: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && files.isEmpty }
    /// The draft as the page holds it this moment — what the wall's store is handed at every change.
    private var draft: MTBoardDraft { MTBoardDraft(text: text, files: files, at: at, lp: linkCard?.json) }
    /// The post as the wall will draw it: the very shape its wall shows on its way (MTBoard.fresh).
    private var draftPost: MTBoardSeen { draft.seen(on: owner) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    MTBoardCell(post: draftPost, owner: owner, onComments: {},
                                draft: MTBoardDrafting(text: $text, focus: $textFocused, sources: files.map { $0.url },
                                                       open: sending == nil,
                                                       onTile: { i in if sending == nil, i < files.count { frame(files[i]) } }))
                        .contentShape(Rectangle())
                        .onTapGesture { if sending == nil, !textFocused { textFocused = true } }   // the whole post is the field's (24.09)
                }
                .listRowInsets(EdgeInsets()).listRowBackground(Color.clear).listRowSeparator(.hidden)
                if sending == nil {
                    Section {
                        // A FILM AS THE LIBRARY KEEPS IT (06.10): no re-encoding on its way in (.current), and the library's names
                        // ride with the picks, so the library's own road answers when the picker's hand-over refuses (takeFilm).
                        PhotosPicker(selection: $picks, maxSelectionCount: MTBoard.mediaLimit, matching: .any(of: [.images, .videos]),
                                     preferredItemEncoding: .current, photoLibrary: .shared()) {
                            Label("Photos and videos", systemImage: "photo.on.rectangle")
                        }
                        Button { importing = true } label: {
                            Label("Tracks and files", systemImage: "music.note.list")
                        }
                    }
                    .listRowBackground(MTGlassRowPlate())
                    if !files.isEmpty || 0 < taking {
                        Section {
                            ForEach(files) { f in attached(f) }
                                .onDelete { files.remove(atOffsets: $0) }
                            // A FILM ON ITS WAY FROM THE LIBRARY (06.10): the platform's wheel where its row will stand.
                            if 0 < taking { ProgressView().frame(maxWidth: .infinity, minHeight: 44) }
                        }
                        .listRowBackground(MTGlassRowPlate())
                    }
                }
                if failed {
                    Section { Text("Could not post").foregroundColor(.red) }
                        .listRowBackground(MTGlassRowPlate())
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)   // no grey ground: the sheet's own glass shows through (25.09)
            // THE WALL'S OWN WIDTH: the page's side margin is the one the wall's pages lay (MontanaPeerInfoScreen, My
            // page) — the post here stands exactly as wide as it will on the wall.
            .contentMargins(.horizontal, MTPageEdge.side, for: .scrollContent)
            .safeAreaInset(edge: .top, spacing: 0) {
                if let pid = sending, let o = board.outgoing[pid] {
                    MTBoardProgress(o: o, onRetry: { retry(pid) })
                        .padding(.horizontal).padding(.vertical, 6)
                }
            }
            .navigationTitle("New post")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { MontanaCloseMark { closed = true; leave() } }   // the draft stays (25.09)
                ToolbarItem(placement: .confirmationAction) {
                    // OUR SEND (the author's word 06.10.2026 00:3x MSK: «put our symbol of sending time on the send button»): the
                    // mark every sending of time wears (MTTimeSendMark) on the bar's round plate, as the coins' page sends; it waits
                    // while a pick is still on its way, so no post leaves without the film it was given.
                    if sending == nil {
                        Button { post() } label: { MTBarRoundMark(ringed: false) { MTTimeSendMark(height: 22) } }
                            .buttonStyle(.plain)
                            .disabled(empty || 0 < taking)
                            .opacity(empty || 0 < taking ? 0.4 : 1)
                            .accessibilityLabel(Text("Publish"))
                    }
                }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.audio, .item], allowsMultipleSelection: true) { result in
                if case .success(let urls) = result { for u in urls { take(u) } }
            }
            .onChange(of: picks) { _, items in
                guard !items.isEmpty else { return }
                Task { await load(items) }
            }
            // EVERY CHANGE IS LAID INTO THE WALL'S STORE (25.09): the words as they are typed, a file the moment it is picked or
            // taken off, a frame the moment it is set — the page holds nothing the store does not.
            .onChange(of: text) { _, _ in lookLink(text); lay() }
            .onChange(of: files) { _, _ in lay() }
            .onAppear { textFocused = true; lookLink(text) }
            .onDisappear { board.draftShown() }   // the wall under the page draws the draft as it was left
            .onChange(of: textFocused) { _, f in MontanaP2PTrace.mark("post_field", f ? "focus" : "unfocus") }
            // THE PICTURE'S FRAME (the author's word 24.09: «editing of the photo — its size, the field of it the post
            // shows»): the one crop of the app, with the shapes a post takes under it as miniatures of the picture.
            .fullScreenCover(item: $framing) { f in
                MTFrameCropView(image: f.image, rim: .tile, shapes: MTBoardFrame.shapes, start: f.frame) { kept in
                    if let kept, let k = files.firstIndex(where: { $0.id == f.id }) { files[k].fr = kept }
                    framing = nil
                    MontanaP2PTrace.mark("post_frame", kept == nil ? "left" : "set")
                }
            }
        }
        // ONE PAGE, ONE DRESS (the author's word 25.09: «the write button calls the page of the owner of this function, one —
        // the one from the feed is crooked and in other colours»): the page's own tint, the chat's — opened from the feed it
        // wore the chats page's gold.
        .tint(.primary)
        .modifier(MTGlassSheet())   // THE NEW POST'S PAGE IS GLASS (the author's word 25.09), not a dead grey ground
        .montanaMotionMeter()       // its rise and fall on the platform's sheet, measured (25.09)
    }

    /// The first link of the words becomes the card the post will carry, while the page is still open.
    private func lookLink(_ words: String) {
        guard MTLinkPreviewBuilder.enabled else {
            linkCard = nil
            linkURL = ""
            return
        }
        guard let first = MTLinkPreviewBuilder.webURLs(in: words).first else {
            linkCard = nil
            linkURL = ""
            return
        }
        let key = first.absoluteString
        if key == linkURL { return }
        linkURL = key
        linkCard = nil
        linkGen += 1
        let gen = linkGen
        let wall = owner
        Task {
            let made = await MTLinkPreviewBuilder.wallCard(in: key)
            await MainActor.run {
                guard gen == linkGen else { return }
                linkCard = made
                guard var held = MTBoard.shared.draft(on: wall) else { return }
                guard MTLinkPreviewBuilder.firstWebURL(in: held.text)?.absoluteString == key else { return }
                held.lp = made?.json
                MTBoard.shared.lay(draft: held, on: wall)
                MTBoard.shared.draftShown()
            }
        }
    }

    /// The page leaves by its own close — the platform's sheet it stands on (present) — as every page over the chat does.
    private func leave() { mtLeavePage(montanaClose, dismiss) }
    /// What the page holds goes to the wall's store; while the post is on its way the page holds nothing of its own.
    private func lay() {
        guard sending == nil else { return }
        board.lay(draft: draft, on: owner)
    }

    /// A file of the post, under it: its miniature — a picture in its frame — its name and its size; a touch on a picture
    /// opens its frame, the cross takes the file off the post.
    private func attached(_ f: MTBoardDraftFile) -> some View {
        let visual = f.kind == "img" || f.kind == "vid"
        return HStack(spacing: 8) {
            Button { if visual { frame(f) } } label: {
                HStack(spacing: 12) {
                    if visual {
                        MTBoardPicture(media: MTBoardMedia(kind: f.kind, name: f.name, ext: f.ext, size: f.size, key: "",
                                                           chunks: [], fr: f.fr), source: f.url)
                            .frame(width: 44, height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    } else {
                        Image(systemName: f.kind == "aud" ? "music.note" : "doc")
                            .font(.system(size: 17, weight: .semibold)).foregroundColor(.secondary)
                            .frame(width: 44, height: 44)
                            .background(Color(white: 0.16), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        // USER-DATA: the file's own name
                        Text(verbatim: f.name).foregroundColor(.primary).lineLimit(1)
                        Text(mtSize(f.size)).font(.caption).foregroundColor(.secondary)
                    }
                    Spacer(minLength: 0)
                    if visual { Image(systemName: "crop").foregroundColor(.secondary) }
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            cross(f)
        }
    }
    private func cross(_ f: MTBoardDraftFile) -> some View {
        Button { files.removeAll { $0.id == f.id } } label: {
            Image(systemName: "xmark.circle.fill").font(.system(size: 22))
                .symbolRenderingMode(.hierarchical).foregroundStyle(.secondary)
                .frame(width: 44, height: 44).contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(Text("Remove"))
    }

    /// The picture's frame opens on the picture itself, upright, as large as the page draws it.
    private func frame(_ f: MTBoardDraftFile) {
        let id = f.id, url = f.url, kind = f.kind
        Task {
            guard let img = await Task.detached(priority: .userInitiated, operation: {
                MTBoardImage.upright(url, kind: kind, longest: 2048)
            }).value, 0 < img.size.width, 0 < img.size.height else { return }
            let now = files.first(where: { $0.id == id })?.fr ?? MTBoardFrame.own(img.size)
            framing = Framing(id: id, image: img, frame: now)
        }
    }

    /// A FILE COMES INTO THE WALL'S DRAFTS FOLDER THE MOMENT IT IS PICKED (25.09), off the main thread: a picked file lived in
    /// the temporary folder, which the system empties between runs, and the page copied it there on the main thread.
    private func take(_ u: URL) {
        let ext = u.pathExtension, name = u.lastPathComponent, kind = MTPostMeasure.kind(ofExtension: ext)
        Task.detached(priority: .userInitiated) {
            guard let f = MTBoardDrafts.take(u, kind: kind, name: name, ext: ext, move: false) else { return }
            await MainActor.run { add(f) }
        }
    }

    /// THE PICK COMES AS THE CHAT'S DOES, AND EVERY STEP OF IT IS WRITTEN (the author's word 06.10.2026 00:3x MSK: «why can't I
    /// attach a video to a new post on T1»). T1 held this page open from 00:30:02 to 00:32:56 and nothing came: not a line in the
    /// diary, not a file in the drafts folder, not a copy in the temporary one -- the road wrote nothing and its refusals fell
    /// silent (try?), and a film came through the picker's automatic encoding, which re-encodes a long film for minutes with
    /// nothing on the page. Now a film comes as the library keeps it (.current); when the picker's hand-over refuses, the
    /// library's own road answers (PHImageManager, the chat's road, the network allowed for a film kept in iCloud); every pick
    /// leaves its line -- its kind, its wait, its size, or the refusal in the system's words -- and the page wears the
    /// platform's wheel meanwhile.
    private func load(_ items: [PhotosPickerItem]) async {
        await MainActor.run { taking += items.count }
        MontanaP2PTrace.mark("post_pick", "n=\(items.count)")
        for item in items {
            let t0 = Date()
            let film = item.supportedContentTypes.contains { $0.conforms(to: .movie) }
            let f = await (film ? takeFilm(item) : takePicture(item))
            let ms = Int(Date().timeIntervalSince(t0) * 1000)
            if let f {
                MontanaP2PTrace.mark("post_pick", "kind=\(f.kind) ms=\(ms) mb=\(f.size / 1_048_576)")
                await MainActor.run { add(f) }
            } else {
                MontanaP2PTrace.mark("post_pick", "none kind=\(film ? "vid" : "img") ms=\(ms)")
            }
            await MainActor.run { taking -= 1 }
        }
        await MainActor.run { picks = [] }
    }
    private func takeFilm(_ item: PhotosPickerItem) async -> MTBoardDraftFile? {
        do {
            if let movie = try await item.loadTransferable(type: ChatMovie.self) {
                let ext = movie.url.pathExtension.isEmpty ? "mov" : movie.url.pathExtension
                // The transferable's copy is the page's own: it moves into the folder, no second copy of a film.
                return MTBoardDrafts.take(movie.url, kind: "vid", name: movie.url.lastPathComponent, ext: ext, move: true)
            }
            MontanaP2PTrace.mark("post_pick", "REFUSED kind=vid by=picker -- it handed no film")
        } catch {
            MontanaP2PTrace.mark("post_pick", "REFUSED kind=vid by=picker -- \(error.localizedDescription)")
        }
        guard let id = item.itemIdentifier,
              let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject else {
            MontanaP2PTrace.mark("post_pick", "REFUSED kind=vid by=library -- it names no such film")
            return nil
        }
        let opts = PHVideoRequestOptions()
        opts.isNetworkAccessAllowed = true
        opts.deliveryMode = .highQualityFormat
        return await withCheckedContinuation { done in
            PHImageManager.default().requestAVAsset(forVideo: asset, options: opts) { av, _, info in
                guard let u = (av as? AVURLAsset)?.url else {
                    let why = (info?[PHImageErrorKey] as? Error)?.localizedDescription ?? "it handed no file"
                    MontanaP2PTrace.mark("post_pick", "REFUSED kind=vid by=library -- \(why)")
                    done.resume(returning: nil)
                    return
                }
                let ext = u.pathExtension.isEmpty ? "mov" : u.pathExtension
                done.resume(returning: MTBoardDrafts.take(u, kind: "vid", name: u.lastPathComponent, ext: ext, move: false))
            }
        }
    }
    private func takePicture(_ item: PhotosPickerItem) async -> MTBoardDraftFile? {
        do {
            if let data = try await item.loadTransferable(type: Data.self) {
                let ext = item.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg"
                return MTBoardDrafts.take(data, kind: MTPostMeasure.kind(ofExtension: ext), ext: ext)
            }
            MontanaP2PTrace.mark("post_pick", "REFUSED kind=img by=picker -- it handed no picture")
        } catch {
            MontanaP2PTrace.mark("post_pick", "REFUSED kind=img by=picker -- \(error.localizedDescription)")
        }
        return nil
    }
    /// A file joins the post with what the post shows of it — its size and a length came with it from the folder — and a
    /// picture's frame: its own shape whole, read off the page from a small copy, until its writer sets another.
    private func add(_ f: MTBoardDraftFile) {
        files.append(f)
        let id = f.id, url = f.url, kind = f.kind
        guard kind == "img" || kind == "vid" else { return }
        Task {
            let seen = await Task.detached(priority: .userInitiated) { MTBoardImage.upright(url, kind: kind, longest: 256)?.size }.value
            guard let seen, 0 < seen.width, 0 < seen.height,
                  let k = files.firstIndex(where: { $0.id == id }), files[k].fr == nil else { return }
            files[k].fr = MTBoardFrame.own(seen)
        }
    }

    /// THE CHECK: the post is taken into the wall's store as it will stand (begin) — from that moment the draft is the post's
    /// (dropped, its files copied into the media store) — and its files go to the node under the bar; the page leaves when
    /// the post is out. A post the store could not take stays a draft, and the page says so.
    private func post() {
        guard sending == nil, !empty else { return }
        failed = false
        let atts = files.map { MTBoard.Attachment(url: $0.url, kind: $0.kind, name: $0.name, ext: $0.ext, frame: $0.fr) }
        let words = text, wall = owner
        sending = ""   // the check stands down at once; the bar comes with the post
        Task {
            let json = MTLinkPreviewBuilder.firstWebURL(in: words)?.absoluteString == linkCard?.u ? linkCard?.json : nil
            guard let pid = await MTBoard.shared.begin(on: wall, text: words, attachments: atts, card: json) else {
                await MainActor.run { sending = nil; failed = true }
                return
            }
            await MainActor.run { sending = pid; MTBoard.shared.dropDraft(on: wall, why: "posted") }
            let ok = await MTBoard.shared.publish(pid)
            await MainActor.run { if ok && !closed { leave() } }
        }
    }
    /// The files the node did not take are laid again, from where the node left them.
    private func retry(_ pid: String) {
        Task {
            let ok = await MTBoard.shared.publish(pid)
            await MainActor.run { if ok && !closed { leave() } }
        }
    }
}

/// THE NEW POST'S PAGE RISES AS A TREE OF ITS OWN (25.09, P1: at 14:20 the page's bar stood at 79 % of a post the node had taken
/// whole a second before, and the page never closed; at 14:07 a return from another app found the page reset). The page was a
/// sheet of the wall's tree — a child of whatever page drew the wall, living and dying with that tree's passes. Now it is the
/// platform's own sheet, hosted by itself over the topmost screen, wherever the wall is drawn: no page under it builds it anew
/// or stops its updates, and it leaves by its own close (montanaClose). Its state lives in the wall's store (MTBoardDraft), so
/// a page reopened is the page as it was left. THE ONE BIRTH of the page: the owner guard holds it to this place alone.
extension MTBoardComposer {
    private final class Hold { weak var host: UIViewController? }
    /// The page on the screen now, held weakly: a page let go by the platform is no longer named.
    private static weak var shown: UIViewController?
    static func present(on wall: String?) {
        let hold = Hold()
        let h = MontanaHost.make(MTBoardComposer(owner: wall).environment(\.montanaClose, { if let v = hold.host { MTTop.dismiss(v, kind: "composer") } }))
        hold.host = h
        shown = h
        h.view.backgroundColor = .clear
        h.modalPresentationStyle = .pageSheet
        MontanaP2PTrace.mark("post_page", "open wall=\(wall == nil ? "mine" : "theirs") draft=\(MTBoard.shared.draft(on: wall) == nil ? 0 : 1)")
        MTTop.present(h, kind: "composer")   // the one door of every modal (25.09)
    }
    /// THE SHARE MENU'S POST OPENS THE PAGE THE WALL'S WRITE BUTTON OPENS (the author's word 02.10 19:17): the store's draft
    /// has just taken the shared words and files (MTBoard.takeFromSheet); a page already up holds its own copy of the draft
    /// from its opening, so it is closed first -- everything it held is already in the store -- and the page rises again
    /// over the draft as the store now holds it.
    static func reopen(on wall: String?) {
        guard let v = shown, v.presentingViewController != nil, !v.isBeingDismissed else { present(on: wall); return }
        MontanaP2PTrace.mark("post_page", "again wall=\(wall == nil ? "mine" : "theirs") -- the share menu laid the draft")
        MTTop.dismiss(v, kind: "composer") { present(on: wall) }
    }
}

/// A POST OF MINE, ITS WORDS CHANGED (the author's word 30.09: «make publications editable»): the post as it stands on its wall,
/// its words a field where they stand, on the new post's glass; the checkmark gives the words to the wall (MTBoard.edit), the
/// cross leaves them as they were. Only the words: a file keeps the name its place gave it at birth.
struct MTBoardEditor: View {
    let post: MTBoardSeen
    @Environment(\.dismiss) private var dismiss
    @Environment(\.montanaClose) private var montanaClose
    @State private var text: String
    @FocusState private var textFocused: Bool

    init(post: MTBoardSeen) {
        self.post = post
        _text = State(initialValue: post.text)
    }

    private var changed: Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return t != post.text && (!t.isEmpty || !post.media.isEmpty)
    }
    /// The post's files as this phone keeps them -- the writer is their first keeper.
    private var sources: [URL] {
        post.media.indices.map { MontanaMediaStore.url(MTBoard.fileName(post.id, $0, post.media[$0].ext)) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    MTBoardCell(post: post, owner: nil, onComments: {},
                                draft: MTBoardDrafting(text: $text, focus: $textFocused, sources: sources, open: true, onTile: { _ in }))
                        .contentShape(Rectangle())
                        .onTapGesture { if !textFocused { textFocused = true } }
                }
                .listRowInsets(EdgeInsets()).listRowBackground(Color.clear).listRowSeparator(.hidden)
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .contentMargins(.horizontal, MTPageEdge.side, for: .scrollContent)
            .navigationTitle("Edit post")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { MontanaCloseMark { leave() } }
                ToolbarItem(placement: .confirmationAction) { MontanaDoneMark { save() }.disabled(!changed) }
            }
            .onAppear { textFocused = true }
        }
        .tint(.primary)
        .modifier(MTGlassSheet())
        .montanaMotionMeter()
    }

    private func leave() { mtLeavePage(montanaClose, dismiss) }
    private func save() {
        guard changed else { return }
        MTBoard.shared.edit(post.id, words: text)
        leave()
    }
}

extension MTBoardEditor {
    private final class Hold { weak var host: UIViewController? }
    static func present(_ post: MTBoardSeen) {
        let hold = Hold()
        let h = MontanaHost.make(MTBoardEditor(post: post).environment(\.montanaClose, { if let v = hold.host { MTTop.dismiss(v, kind: "post_edit") } }))
        hold.host = h
        h.view.backgroundColor = .clear
        h.modalPresentationStyle = .pageSheet
        MontanaP2PTrace.mark("post_page", "edit chars=\(post.text.count)")
        MTTop.present(h, kind: "post_edit")
    }
}

/// The comments of a post, and the field to add one.

struct MTBoardChainPage: View {
    let post: MTBoardSeen
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section {
                    if post.comments.isEmpty {
                        Text("No comments yet").foregroundStyle(.secondary)
                    } else {
                        if let first = post.comments.first, let last = post.comments.last {
                            // USER-DATA: the interval this comment chain covers
                            Text(verbatim: MTBoard.local(first.at) + " · " + MTBoard.local(last.at))
                                .font(.subheadline).textSelection(.enabled)
                        }
                        ForEach(post.comments) { c in
                            // USER-DATA: one seal of the comment chain
                            Button { MTBoardComments.present(post: post.id, comment: c.id) } label: {
                                Text(verbatim: c.h == nil ? MTBoard.local(c.at) : MTBoard.sealLine(c))
                                    .font(.caption).textSelection(.enabled)
                                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } header: { Text("TimeChain") }
            }
            .navigationTitle("TimeChain")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { MontanaCloseMark { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    MontanaBarMark(glyph: "square.and.arrow.up", label: "Share") {
                        // THE CHAIN GOES WITH ITS POST'S LINK (the author's word 02.10 19:26: «share the chain -- the link
                        // arrives crooked and cannot be tapped»): the file keeps the records, the link ahead of it opens the post.
                        let held = MTBoard.shared.place(of: post.id)
                        var items: [Any] = []
                        if let link = MTPostLinkItem(post, on: held == "" ? nil : held) { items.append(link) }
                        if let url = MTBoard.chainFile(post) { items.append(url) }
                        if !items.isEmpty { MTShare.present(items) }
                    }
                }
            }
        }
    }
}

/// A POST GOES OUT AS ITS SHORT LINK WITH THE SYSTEM'S OWN CARD OF IT (the author's word 02.10 15:08): the receiver's
/// sheet and chat see the writer, the words and the picture before opening; the link opens the post itself.
final class MTPostLinkItem: NSObject, UIActivityItemSource {
    let url: URL
    let title: String
    let image: UIImage?
    init?(_ p: MTBoardSeen, on wall: String?) {
        guard let u = URL(string: MTBoard.linkPost(p, on: wall)) else { return nil }
        url = u
        let words = p.text.trimmingCharacters(in: .whitespacesAndNewlines)
        title = words.isEmpty ? p.byName : p.byName + " · " + String(words.prefix(160))
        image = p.media.lazy.compactMap { MTBoardFace.picture($0.thumb) }.first ?? MTBoardFace.picture(p.face)
    }
    static func present(_ p: MTBoardSeen, on wall: String?) {
        guard let item = MTPostLinkItem(p, on: wall) else { return }
        MTShare.present([item])
    }
    func activityViewControllerPlaceholderItem(_ controller: UIActivityViewController) -> Any { url }
    /// THE LINK AS A PERSON READS IT WHERE IT BECOMES WORDS (the author's word 02.10 19:26: «the link arrives crooked»): a copy
    /// and Montana's own sheet make the link the words of a letter, and a URL hands them its bytes -- a name's letters as
    /// %D0%9A... . There the link goes as its readable words (MTLinks.readable), which the letter's finder makes a link again;
    /// every other door keeps the URL and the system's card of it.
    func activityViewController(_ controller: UIActivityViewController, itemForActivityType type: UIActivity.ActivityType?) -> Any? {
        guard let type else { return url }
        let own = Bundle.main.bundleIdentifier.map { type.rawValue.hasPrefix($0 + ".") } ?? false
        if type == .copyToPasteboard || own { return MTLinks.readable(url) }
        return url
    }
    func activityViewControllerLinkMetadata(_ controller: UIActivityViewController) -> LPLinkMetadata? {
        let m = LPLinkMetadata()
        m.originalURL = url
        m.url = url
        m.title = title
        if let image {
            m.imageProvider = NSItemProvider(object: image)
            m.iconProvider = NSItemProvider(object: image)
        }
        return m
    }
}

struct MTBoardComments: View {
    let postId: String
    let owner: String?
    var focus: String? = nil
    /// A COMMENTER'S FACE OPENS THEIR PAGE (the author's word 25.09: «every button on the posts must work»).
    var onWriter: (MTBoardWriter) -> Void = { _ in }
    @ObservedObject private var board = MTBoard.shared
    @ObservedObject private var fold = MTFilterFold.shared   // the filter's fold, opened for the comment by the person's tap
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""
    @State private var showChain = false

    /// THE ONE THREAD (the author's word 25.09: «the comments belong to the original's access»): the post's own comments, or —
    /// for a repost — its original's, on the wall that holds it, under that wall's rules (MTBoard.thread).
    private var thread: (wall: String?, post: MTBoardSeen)? {
        guard let p = board.posts(on: owner).first(where: { $0.id == postId }) else { return nil }
        return board.thread(of: p, on: owner)
    }

    var body: some View {
        let t = thread
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                List {
                    if let t {
                        MTBoardCell(post: t.post, owner: t.wall, onComments: {}, onWriter: onWriter, onItsWall: false, whole: true)
                            .listRowSeparator(.hidden)
                    }
                    if let t, !t.post.comments.isEmpty {
                        // THE CHAIN, NEWEST FIRST (the author's word 02.10), each under its number in the chain.
                        let base = t.post.commentCount - t.post.comments.count
                        ForEach(Array(t.post.comments.enumerated()).reversed(), id: \.element.id) { i, c in
                            row(c, number: base + i + 1, in: t).id(c.id)
                        }
                    } else if t == nil {
                        // A repost whose original this phone holds nowhere: its comments live with the original, under its rules.
                        Text("The comments are under the original post").foregroundColor(.secondary)
                    } else {
                        Text("No comments yet").foregroundColor(.secondary)
                    }
                }
                // THE KEYS GO DOWN UNDER THE FINGER, AS IN THE CHATS (the author's word 02.10 19:17: «fix the keyboard in the comments so
                // it folds as in the chats»): the list had no dismissal of its own, so the keys stood over the thread until the sheet
                // closed. The platform's interactive dismissal: a drag over the thread takes the keys down with the finger, and the
                // field under the list rides them down on the platform's keyboard safe area.
                .scrollDismissesKeyboard(.interactively)
                .onAppear { if let focus { proxy.scrollTo(focus, anchor: .center) } }
                }
                if let t, board.canWrite(on: t.wall) {
                    HStack(spacing: 8) {
                        TextField("Write a comment", text: $draft, axis: .vertical)
                            .lineLimit(1...5)
                            .padding(.horizontal, 12).padding(.vertical, 10)
                            .background(Color(white: 0.15), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        Button { send() } label: {
                            Image(systemName: "arrow.up.circle.fill").font(.system(size: 30))
                                .frame(width: 44, height: 44).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityLabel(Text("Send"))
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                } else if t != nil {
                    // A COMMENT IS WRITING ON THE WALL (the critic's noticed point 4, 24.09): the owner keeps no comment from one
                    // their rule does not let write, so the field that would send words to nowhere is not drawn.
                    Text("Only people who may write on this wall can comment")
                        .font(.footnote).foregroundColor(.secondary).multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity).padding(.horizontal, 16).padding(.vertical, 14)
                }
            }
            .navigationTitle("Comments")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { MontanaCloseMark { dismiss() } }
                if thread != nil {
                    ToolbarItemGroup(placement: .confirmationAction) {
                        MontanaBarMark(glyph: "clock", label: "TimeChain") { showChain = true }
                        MontanaBarMark(glyph: "square.and.arrow.up", label: "Share") {
                            if let t = thread { MTPostLinkItem.present(t.post, on: t.wall) }
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showChain) {
            if let post = thread?.post { MTBoardChainPage(post: post) }
        }
        .tint(.primary)   // one dress wherever it opens (25.09)
    }

    /// ONE COMMENT UNDER ITS WRITER'S HEAD (the author's words 25.09: «the commenters' faces are still not seen», «in the
    /// comments too the author is clickable, with the avatar»): the comment's head IS the post's head — the one byline, the
    /// face, the name and when, one target over its whole room — for every writer this phone can put a page to: me, the
    /// wall's owner, and on my own wall every commenter. The face is the one a post's writer wears: the face this phone
    /// holds for them, else the small face the comment carries, else their glyph. Another's words carrying an objectionable
    /// word stand folded until the person's tap (Guideline 1.2), as a letter's do.
    private func row(_ c: MTBoardComment, number n: Int, in t: (wall: String?, post: MTBoardSeen)) -> some View {
        let w = board.commenter(c, of: t.post.id, on: t.wall)
        let known: Bool = { if case .unknown = w { return false }; return true }()
        let hidden = w != .me && MontanaSafety.filterOn && !fold.opened.contains(c.id) && MontanaContentFilter.flags(c.text)
        return VStack(alignment: .leading, spacing: 2) {
            MTBoardByline(writer: w, name: c.by, glyph: c.glyph, face: c.fc, at: c.at, onOpen: known ? { onWriter(w) } : nil)
            Group {
                if hidden {
                    Button { withAnimation(.easeOut(duration: 0.15)) { MTFilterFold.shared.open(c.id) } } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Label("Hidden by the filter", systemImage: "eye.slash").font(.callout)
                            Text("Tap to show").font(.caption).foregroundColor(.secondary)
                        }
                        .frame(minHeight: 44).contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                } else {
                    // USER-DATA: the comment's own words
                    if !(c.hid == true && c.text.isEmpty) {
                        Text(MTBoard.linked(c.text)).font(.body)
                    }
                }
            }
            .padding(.leading, 46)   // under the name: the face's 36 points and the gap's 10

            // USER-DATA: the comment's number in its chain and its moment, on this phone's clock and in its zone
            Text(verbatim: MTBoard.numberLine(n, c))
                .font(.caption2).foregroundStyle(.secondary)
                .padding(.leading, 46)
            if t.wall == nil {
                Button { board.hideComment(post: t.post.id, c.id) } label: {
                    Image(systemName: c.hid == true ? "eye" : "eye.slash")
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.leading, 46)
            }
        }
        .contentShape(Rectangle())
        .contextMenu { menu(c, number: n, in: t) }
    }

    /// A COMMENT'S MENU IS THE SYSTEM'S (the author's word 02.10: «a long press on a comment -- the native grey menu, share the
    /// comment and its number»): its short link, its words, its number in the chain.
    @ViewBuilder private func menu(_ c: MTBoardComment, number n: Int, in t: (wall: String?, post: MTBoardSeen)) -> some View {
        Button { if let u = URL(string: MTBoard.linkComment(t.post, n, c, on: t.wall)) { MTShare.present([u]) } } label: {
            Label("Share", systemImage: "square.and.arrow.up")
        }
        if !c.text.isEmpty {
            Button { UIPasteboard.general.string = c.text } label: { Label("Copy", systemImage: "doc.on.doc") }
        }
        Button { UIPasteboard.general.string = String(n) } label: {
            // USER-DATA: the comment's number in its chain
            Label { Text(verbatim: "#" + String(n)) } icon: { Image(systemName: "number") }
        }
    }

    private final class Hold { weak var host: UIViewController? }
    static func present(post id: String, comment: String?) {
        let held = MTBoard.shared.place(of: id)
        let owner: String? = held == "" ? nil : held
        let hold = Hold()
        let page = MTBoardComments(postId: id, owner: owner, focus: comment)
        let h = MontanaHost.make(page.environment(\.montanaClose, { if let v = hold.host { MTTop.dismiss(v, kind: "comments") } }))
        hold.host = h
        h.view.backgroundColor = .clear
        h.modalPresentationStyle = .pageSheet
        MTTop.present(h, kind: "comments")
    }
    static func open(_ url: URL) -> Bool {
        guard let t = target(url) else { return false }
        present(post: t.post, comment: t.comment)
        return true
    }
    /// The post, and the comment, a wall's link names among the posts this phone holds -- read by the tap and the preview alike
    /// (MTPostLinkPeek); nil -- a link of no post held here.
    static func target(_ url: URL) -> (post: String, comment: String?)? {
        guard url.scheme?.lowercased() == "montana", url.host?.lowercased() == "wall" else { return nil }
        let parts = url.path.split(separator: "/").map(String.init)
        // A long link opens a post this phone holds; one it does not hold is answered by the entrance (MontanaMeeting.handleLink),
        // not by an empty page (02.10).
        let held = parts.count >= 2 && MTBoard.shared.place(of: parts[1]) != nil
        if parts.count == 2, parts.first == "post", held { return (parts[1], nil) }
        if parts.count == 3, parts.first == "comment", held { return (parts[1], parts[2]) }
        if parts.count == 2 || parts.count == 3, let head = parts.first, head.hasPrefix("@"), let n = Int(parts[1]),
           let hit = MTBoard.shared.find(name: String(head.dropFirst()), number: n, comment: parts.count == 3 ? Int(parts[2]) : nil) {
            return hit
        }
        return nil
    }
    private func send() {
        guard let t = thread else { return }
        board.comment(t.post, on: t.wall, text: draft)   // to the thread's own wall: a repost's go to its original's owner
        draft = ""
    }
}

/// WHO CAN WRITE ON MY WALL, AND WHO CAN SEE IT (the author's word 24.09): only me, everyone, some — chosen — or
/// everyone but some. One page for both rules.
struct MTBoardRulePage: View {
    let act: MTBoardAct
    @State private var rule: MTBoardRule
    /// The rule as it stands from the first frame (the critic's P9: the page flashed «Everyone» before it read it).
    init(act: MTBoardAct) {
        self.act = act
        _rule = State(initialValue: MTBoardRule.current(act))
    }

    var body: some View {
        List {
            Section {
                ForEach(MTBoardRule.allCases) { r in
                    Button { rule = r; MTBoardRule.choose(r, for: act) } label: {
                        HStack {
                            Text(r.title).foregroundColor(.primary)
                            Spacer()
                            Image(systemName: "checkmark").font(.body.weight(.semibold))
                                .foregroundColor(.accentColor).opacity(rule == r ? 1 : 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .listRowBackground(MTGlassRowPlate())
            if rule == .some || rule == .except {
                Section {
                    NavigationLink { MTBoardPeoplePage(act: act, deny: rule == .except) } label: {
                        Text("Choose people").foregroundColor(.primary)
                    }
                }
                .listRowBackground(MTGlassRowPlate())
            }
        }
        .scrollContentBackground(.hidden)
        .montanaPageGround()   // my page's ground, as the drawer and my page wear it (25.09)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
    private var title: LocalizedStringKey {
        switch act {
        case .write: return "Who can write on my wall"
        case .see: return "Who can see my wall"
        }
    }
}

/// The people a rule names: the correspondents this phone holds a pipe with; the whole row answers the finger.
struct MTBoardPeoplePage: View {
    let act: MTBoardAct
    let deny: Bool
    @State private var chosen: Set<String> = []

    var body: some View {
        let store = ChatStore.live
        let people = (store?.listChats() ?? []).filter { c in
            guard !c.isGroup, let conv = c.convId, !conv.isEmpty, !ChatStore.isLocalRoom(c.name) else { return false }
            return MontanaConv.holds(conv)
        }
        List {
            Section {
                ForEach(people) { c in
                    let conv = c.convId ?? ""
                    Button { toggle(conv) } label: {
                        HStack(spacing: 12) {
                            AvatarCircle(photoURL: store?.avatarFor(c), color: c.color,
                                         initial: store?.initial(for: c) ?? c.initial, size: 36)
                            // USER-DATA: the correspondent's name, as the list shows it
                            Text(verbatim: store?.title(for: c) ?? c.title).foregroundColor(.primary).lineLimit(1)
                            Spacer()
                            Image(systemName: "checkmark").font(.body.weight(.semibold))
                                .foregroundColor(.accentColor).opacity(chosen.contains(conv) ? 1 : 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .listRowBackground(MTGlassRowPlate())
        }
        .scrollContentBackground(.hidden)
        .montanaPageGround()   // my page's ground, as the drawer and my page wear it (25.09)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { chosen = deny ? MTBoardRule.denied(act) : MTBoardRule.allowed(act) }
    }

    private func toggle(_ conv: String) {
        if chosen.contains(conv) { chosen.remove(conv) } else { chosen.insert(conv) }
        if deny { MTBoardRule.setDenied(chosen, for: act) } else { MTBoardRule.setAllowed(chosen, for: act) }
    }
    private var title: LocalizedStringKey {
        switch (act, deny) {
        case (.write, false): return "Who can write"
        case (.write, true): return "Who cannot write"
        case (.see, false): return "Who can see"
        case (.see, true): return "Who cannot see"
        }
    }
}


/// THE POST'S PLATE (the author's word 25.09: «the posts' bubbles on the wall the other way round -- liquid glass, but
/// ONE-TONE»): the system's regular glass -- frosted, one tone over any ground -- in the bubble's own shape (BubbleShape, a
/// correspondent's); the thin material under the bubble's rim before the newest system. The clear glass is the buttons'.
struct MTBoardPostPlate: View {
    var body: some View {
        let shape = BubbleShape(mine: false, tail: false)
        if #available(iOS 26.0, *), MontanaSkin.isNative {
            MTGlassPlate(shape: shape)
        } else {
            shape.fill(MontanaOctagon.barMaterial).overlay(MTBubbleStyle.outline(mine: false, shape))
        }
    }
}

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

/// A POST'S WORDS FOLD (26.09; kept only for posts by the author's word 27.09). A post whose words take more than eight
/// lines shows its first eight, the ellipsis and the chevron; the finger opens the whole post on MTLetterPage. Its
/// size is a function of its words, its type size and its width alone: the list asks it before the row shows, the view lays
/// itself out by it, and both ask TextKit's one stack (MTMessageText.box) -- they cannot answer differently.
struct MTPostText: UIViewRepresentable {
    let text: String
    var onOpen: (() -> Void)? = nil
    /// On the post's own page (02.10): never folded, its links answer the finger.
    var whole = false

    /// The body the post's words have always worn, at the page's own type size.
    static func font(_ env: EnvironmentValues) -> UIFont {
        UIFont.preferredFont(forTextStyle: .body,
                             compatibleWith: UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(env.dynamicTypeSize)))
    }
    func makeUIView(context: Context) -> MTPostTextView { MTPostTextView() }
    func updateUIView(_ v: MTPostTextView, context: Context) {
        if (v.onOpen == nil) != (onOpen == nil) || v.whole != whole { v.setNeedsLayout() }
        v.onOpen = onOpen
        v.whole = whole
        v.show(text, font: Self.font(context.environment))
    }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: MTPostTextView, context: Context) -> CGSize? {
        let offered = proposal.width.flatMap { w in w.isFinite ? w : nil } ?? MTScene.size().width
        return MTPostTextView.size(of: text, font: Self.font(context.environment), width: max(offered, 1), whole: whole)
    }
}

/// The post's words on the platform's text view over TextKit's own stack (the measure's), folded when long, the chevron under.
final class MTPostTextView: UIView, UIGestureRecognizerDelegate {
    var onOpen: (() -> Void)?
    var whole = false
    private let words = MTLinkTextView(usingTextLayoutManager: false)
    private let chevron = UIImageView(image: UIImage(systemName: "chevron.right",
                                                     withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)))
    private let disclosure = UILabel()
    private lazy var tap = UITapGestureRecognizer(target: self, action: #selector(openWhole))
    private var text = ""
    private var font = UIFont.preferredFont(forTextStyle: .body)
    /// The chevron's line under a folded post's eighth line.
    static let chevronLine: CGFloat = 22
    private static func disclosureHeight(font: UIFont) -> CGFloat { max(chevronLine, ceil(font.lineHeight)) }

    override init(frame: CGRect) {
        super.init(frame: frame)
        words.isEditable = false
        words.isSelectable = true   // the platform opens a link only on a view that may be touched
        words.isScrollEnabled = false
        words.backgroundColor = .clear
        words.textContainerInset = .zero
        words.textContainer.lineFragmentPadding = 0
        words.textColor = .label
        words.dataDetectorTypes = []
        words.tintColor = UIColor(MontanaOctagon.platformBlue)
        words.delegate = MTPostLinkPeek.shared   // a post's link: its preview on a hold, its page at a tap (06.10)
        addSubview(words)
        chevron.tintColor = .label
        chevron.contentMode = .center
        chevron.isHidden = true
        chevron.isAccessibilityElement = false
        addSubview(chevron)
        disclosure.text = String(localized: "Show in full")
        disclosure.textColor = UIColor(MontanaOctagon.platformBlue)
        disclosure.font = font
        disclosure.textAlignment = .right
        disclosure.isHidden = true
        addSubview(disclosure)
        tap.isEnabled = false
        tap.delegate = self
        addGestureRecognizer(tap)
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        setContentHuggingPriority(.defaultLow, for: .horizontal)
    }
    required init?(coder: NSCoder) { nil }

    func show(_ t: String, font f: UIFont) {
        guard t != text || f != font else { return }
        text = t
        font = f
        disclosure.font = f
        lay()
        setNeedsLayout()
    }
    /// The words as the view wears them: their links marked by the one finder (MTLinks, a Montana link among them, 02.10).
    private func lay() {
        let look: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.label]
        words.attributedText = MTLinks.marked(text, attributes: look)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let w = bounds.width
        guard w > 1 else { return }
        let fold = !whole && MTPostFold.folds(text, font: font, width: w)
        // A POST IN A LIST OPENS AT A TAP (the author's word 02.10: «a tap on the post opens it at once, its comments under it»):
        // its words take the finger to its page; there they are whole, selectable, their links live.
        let opens = !whole && onOpen != nil
        let lines = fold ? MTPostFold.foldLines : 0
        if words.textContainer.maximumNumberOfLines != lines {
            words.textContainer.maximumNumberOfLines = lines
            words.textContainer.lineBreakMode = fold ? .byTruncatingTail : .byWordWrapping
        }
        // A LINK ANSWERS IN A LIST TOO (the author's word 03.10: «make the site clickable in posts»): where the post
        // folds or opens at a tap, its words take the finger on a link alone and every other point stays the post's; on its
        // own page they take every touch, the selection's too.
        words.takesEveryTouch = !fold && !opens
        tap.isEnabled = fold || opens
        let h = MTMessageText.box(of: text, font: font, maxWidth: w, lines: lines).height
        words.frame = CGRect(x: 0, y: 0, width: w, height: max(h, ceil(font.lineHeight)))
        chevron.isHidden = !fold
        disclosure.isHidden = !fold
        let footerHeight = Self.disclosureHeight(font: font)
        chevron.frame = CGRect(x: w - 22, y: words.frame.maxY, width: 22, height: footerHeight)
        disclosure.frame = CGRect(x: 0, y: words.frame.maxY, width: max(0, chevron.frame.minX - 6), height: footerHeight)
    }

    static func size(of text: String, font: UIFont, width: CGFloat, whole: Bool = false) -> CGSize {
        let fold = !whole && MTPostFold.folds(text, font: font, width: width)
        let h = MTMessageText.box(of: text, font: font, maxWidth: width, lines: fold ? MTPostFold.foldLines : 0).height
        return CGSize(width: width, height: max(h, ceil(font.lineHeight)) + (fold ? disclosureHeight(font: font) : 0))
    }

    /// The post's tap never begins over a link: there the finger is the link's (03.10).
    override func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
        guard g === tap else { return super.gestureRecognizerShouldBegin(g) }
        return !words.link(at: g.location(in: words))
    }

    @objc private func openWhole() {
        guard let onOpen else { return }
        MontanaP2PTrace.mark("post_words", "open chars=\(text.count)")
        onOpen()
    }
}

/// A POST'S LINK ANSWERS AS THE PLATFORM'S LINKS DO (the author's word 06.10.2026 00:3x MSK: «the internal links to a post must
/// be clickable and handy for a preview of the post and the way to it»): a tap opens the post's page at once, here, by the one
/// road of every link (MontanaMeeting.handleLink), with no round through the system; a hold rises the platform's own preview -- the
/// post as its wall draws it -- with its menu: open, share, copy the link. A link of a post this phone does not hold offers the
/// menu alone; every other link keeps the platform's own tap and hold. One delegate for every text view that carries links.
final class MTPostLinkPeek: NSObject, UITextViewDelegate {
    static let shared = MTPostLinkPeek()
    private var shown: UIViewController?   // the latest preview's host, held while its preview may stand
    private static func wall(_ url: URL) -> Bool { url.scheme?.lowercased() == "montana" && url.host?.lowercased() == "wall" }

    func textView(_ textView: UITextView, primaryActionFor textItem: UITextItem, defaultAction: UIAction) -> UIAction? {
        guard case .link(let url) = textItem.content, Self.wall(url) else { return defaultAction }
        return UIAction { _ in MontanaMeeting.handleLink(url) }
    }
    func textView(_ textView: UITextView, menuConfigurationFor textItem: UITextItem,
                  defaultMenu: UIMenu) -> UITextItem.MenuConfiguration? {
        guard case .link(let url) = textItem.content, Self.wall(url) else { return .init(preview: .default, menu: defaultMenu) }
        let menu = UIMenu(children: [
            UIAction(title: String(localized: "Open"), image: UIImage(systemName: "arrow.up.forward.app")) { _ in MontanaMeeting.handleLink(url) },
            UIAction(title: String(localized: "Share"), image: UIImage(systemName: "square.and.arrow.up")) { _ in MTShare.present([url]) },
            UIAction(title: String(localized: "Copy link"), image: UIImage(systemName: "link")) { _ in UIPasteboard.general.url = url },
        ])
        guard let t = MTBoardComments.target(url), let held = MTBoard.shared.place(of: t.post) else { return .init(menu: menu) }
        let owner: String? = held.isEmpty ? nil : held
        guard let post = MTBoard.shared.posts(on: owner).first(where: { $0.id == t.post }) else { return .init(menu: menu) }
        let width = min(textView.window?.bounds.width ?? MTScene.size().width, 430) - 2 * MTPageEdge.side
        let host = MontanaHost.make(MTBoardCell(post: post, owner: owner, onComments: {}, onItsWall: false).frame(width: width))
        host.view.backgroundColor = .clear
        let fit = host.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude))
        host.view.frame = CGRect(x: 0, y: 0, width: width, height: min(fit.height, 560))
        shown = host
        MontanaP2PTrace.mark("link_peek", "post media=\(post.media.count) h=\(Int(fit.height))")
        return .init(preview: .view(host.view), menu: menu)
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

/// A ROUND GLASS PLATE (the author's word 26.09: «the network page's tab buttons VPN, mesh, P2P must be round»): the system's
/// regular glass in a circle where it has it, the thin material before.
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

/// A REPOST ON ITS WAY (the author's word 25.09: «pressing repost shows the same progress bar as a post's publishing»): the bar
/// a post goes out under, over the post it takes, live on its own — on the wall's page and in the feed alike (the critic 25.09:
/// a repost pressed in the feed showed no bar), with its try-again and its let-go when the files did not all come.
struct MTRepostBar: View {
    let postId: String
    let wall: String?
    @ObservedObject private var board = MTBoard.shared
    var body: some View {
        if let r = board.reposting[postId], r.wall == wall {
            MTBoardProgress(o: r, onRetry: { Task { await MTBoard.shared.repost(r.post, from: r.wall ?? "") } },
                            onDiscard: { MTBoard.shared.letRepostGo(r.id) })
        }
    }
}

/// ONE POST OF THE FEED: the wall it stands on, by reference on this phone ("" — my own), and the post as its owner carried it.
struct MTBoardFeedItem: Identifiable {
    let wall: String
    let post: MTBoardSeen
    var id: String { wall + "#" + post.id }
    /// The wall as the wall's views name it: nil — my own.
    var owner: String? { wall.isEmpty ? nil : wall }
}

/// A POST ON ITS WAY, READ LIVE BY ITS NAME (25.09): the feed's list hosts its cells outside the page's tree and draws a cell
/// anew only when its print moves; the post's bar reads the board itself, so its share moves with every piece the node
/// confirms, wherever the post is written from.
struct MTBoardSendingLive: View {
    let pid: String
    var onWriter: (MTBoardWriter) -> Void = { _ in }
    @ObservedObject private var board = MTBoard.shared
    var body: some View {
        if let o = board.outgoing[pid] { MTBoardSendingCell(o: o, owner: o.wall, onWriter: onWriter) }
    }
}

/// MY DRAFT, READ LIVE BY THE FEED'S ROW (25.09), as a post on its way is: the row stands, its cell reads the board itself.
struct MTBoardDraftLive: View {
    @ObservedObject private var board = MTBoard.shared
    var body: some View {
        if let d = board.draft(on: nil) { MTBoardDraftCell(draft: d, owner: nil) }
    }
}

/// THE FEED (the author's words 25.09: «a tap on the logo opens the feed of the posts on the walls of all my contacts, sorted by
/// time», «the feed in the style of the other pages — the chats, the calls — with the same ground and no border at the top or
/// the bottom», «every post of all my contacts, and the reposts too», «the feed page as whole as the chats, the calls and the
/// contacts, turning sideways as they do», «on the feed, bottom right, as on the chats page, the write button with the same
/// glyph — a new post on my own page»): a page under the time panel as the calls are — the one container of the pages under
/// the bar (MontanaTimePanelList), its ground, its rows running on to the screen's edges — each post in the wall's own cell,
/// the posts on their way first, then the most seen (the author's words 06.10: «rank by views» -- «only the feed»).
/// What stands here is what the walls' owners carried to this phone. A post on the screen is named to its wall's owner once
/// (MTBoard.view, the author's word 06.10: «people, only the number»), who counts it and shows nobody who; nothing else
/// of a look leaves the phone (the critic's P1). The sheets and the pages rise from the page itself (MTBoardPresenting), never
/// from a cell the list may let go.
struct MTFeedTabView: View {
    let panel: MontanaTimePanel
    /// THE FEED'S OWN SEARCH (the author's word 25.09: «the search on the feed page works on the feed itself — its text, every
    /// attachment, the posts, the people, the tracks' and the files' names»): the word at the head narrows the posts, as the
    /// music's does; nothing leaves the phone and no results stand over the rows (MTFeedTabView.matches).
    var query = ""
    /// «Write» stands over the rows, save while the search holds the page — as on the chats page.
    var writes = true
    /// Room kept at the bottom for the floating player (the chats page's reserve, 26.09): the posts scroll under it, «Write» above it.
    var reserve: CGFloat = 0
    @ObservedObject private var board = MTBoard.shared
    @State private var sheet: MTBoardSheet? = nil
    @State private var page: MTBoardRoute? = nil
    @Environment(\.mtPaneLive) private var live   // the feed is looked at (25.09): the moment it is, every wall it draws is asked for
    private static let outMark = "out#"
    private static let draftMark = "draft#"   // my own draft, over the posts on their way (25.09)

    var body: some View {
        let _ = MTFrameMeter.shared.body("feed")   // the page's passes while a motion is measured
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let going = board.outgoing.values.filter { Self.matches($0.post, wall: $0.wall, q) }.sorted { $1.post.at < $0.post.at }
        let items = board.feed().filter { Self.matches($0.post, wall: $0.owner, q) }
        let byRow = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let mine = q.isEmpty ? board.draft(on: nil) : nil   // my own draft stands first (the author's word 25.09), not under a search
        let rows = (mine == nil ? [] : [Self.row(Self.draftMark)]) + going.map { Self.row(Self.outMark + $0.id) } + items.map { Self.row($0.id) }
        // THE COINS MINT OVER THE NEWEST (02.10), wherever the views set it in the feed (06.10).
        let newest = items.max { MTBoard.lastAt($0.post) < MTBoard.lastAt($1.post) }?.id
        ZStack(alignment: .top) {
            MontanaTimePanelList(panel: panel, rows: rows,
                                 fingerprint: { c in Self.print(byRow[c.id]) + [c.id == newest ? 1 : 0] },
                                 swipeLeading: { _ in [] }, swipeTrailing: { _ in [] }, swipesEnabled: false,
                                 onOpen: { _ in },
                                 rowContent: { c in AnyView(cell(c.id, byRow[c.id], top: c.id == newest)) },
                                 bottomReserve: reserve, page: "feed")
                // The author's post icon opens the composer through its one presenter.
                // THE WRITE AS THE CHATS' WRITE (the author's word 01.10 00:42: «on the wall fix the style as on the chats»): the same
                // glyph on the bar's plate, in the pages' one corner.
                .mtPageAction(reserve: reserve, shown: writes) {
                    Button { MTBoardComposer.present(on: nil) } label: {
                        Image(systemName: ContactsTabView.writeGlyph).font(.system(size: 27, weight: .medium)).foregroundColor(MontanaOctagon.barGlyph)
                    }
                    .buttonStyle(.montanaOctagon(square: true, bar: true))
                }
            if items.isEmpty && going.isEmpty && mine == nil {
                Group {
                    if q.isEmpty { Text("Posts on your people's walls\nwill appear here") } else { Text("Nothing found") }
                }
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)
            }
        }
        // THE LOOK ASKS (the author's word 25.09): the feed asks for every wall of my people this phone does not hold, or holds
        // stale, the moment the feed is looked at — at its birth and at every turn to it (mtPaneLive), not at a return of the
        // app alone (MTBoard.lookFeed).
        .onAppear { if live { board.lookFeed() } }
        .onChange(of: live) { _, on in if on { board.lookFeed() } }
        .modifier(MTBoardPresenting(sheet: $sheet, page: $page))
    }
    private static func row(_ id: String) -> Chat {
        Chat(name: id, lastMessage: "", time: "", unread: 0, status: "", convId: id)
    }
    /// Every word a post carries — its words, its writer's name, the wall it stands on, the wall it was taken from, every
    /// file's name (a track's, a document's, a picture's), every comment and its writer — in the platform's own comparison
    /// (localizedStandardContains: letter case and marks aside, as the system's search compares); every word typed must be
    /// found among them.
    static func matches(_ p: MTBoardSeen, wall: String?, _ q: String) -> Bool {
        guard !q.isEmpty else { return true }
        var said = [p.text, p.byName, p.from ?? "", wall.map { MTBoard.nameOf($0) } ?? E2E.myDisplayName()]
        said += p.media.map { $0.name }
        for c in p.comments { said.append(c.by); said.append(c.text) }
        let all = said.joined(separator: "\n")
        return q.split(whereSeparator: { $0.isWhitespace }).allSatisfy { all.localizedStandardContains(String($0)) }
    }
    /// What of a post moves its row: its marks and counts — never its posters, which are heavy to hash and never change. A
    /// post on its way is read live (MTBoardSendingLive) and never moves its row.
    private static func print(_ it: MTBoardFeedItem?) -> [Int] {
        guard let p = it?.post else { return [0] }
        return [p.likes, p.commentCount, p.keepers, p.reposts, p.downloads, p.liked ? 1 : 0, p.kept ? 1 : 0,
                p.reposted ? 1 : 0, p.media.count, p.text.count, Int(p.at), Int(MTBoard.lastAt(p)), p.pinned ? 1 : 0, p.views ?? -1]
    }
    @ViewBuilder private func cell(_ id: String, _ it: MTBoardFeedItem?, top: Bool = false) -> some View {
        if id == Self.draftMark {
            MTBoardDraftLive().padding(.horizontal, MTPageEdge.side).padding(.vertical, 6)
        } else if id.hasPrefix(Self.outMark) {
            MTBoardSendingLive(pid: String(id.dropFirst(Self.outMark.count)), onWriter: open)
                .padding(.horizontal, MTPageEdge.side).padding(.vertical, 6)
        } else if let it {
            VStack(alignment: .leading, spacing: 4) {
                MTRepostBar(postId: it.post.id, wall: it.owner)   // the feed's repost shows its bar too (the critic 25.09)
                if it.post.own != true { wallLink(it) }
                MTBoardCell(post: it.post, owner: it.owner, onComments: { sheet = .comments(it.post.id, it.owner) },
                            onWriter: open, onItsWall: false, onReport: { sheet = .reporting(it.post, on: it.owner) },
                            onOpenWords: { sheet = .comments(it.post.id, it.owner) },
                            onShow: { i in page = .media(MTBoardShow(pid: it.post.id, at: i, owner: it.owner,
                                                                      feed: query.trimmingCharacters(in: .whitespacesAndNewlines))) })
            }
            .padding(.horizontal, MTPageEdge.side).padding(.vertical, 6)
        }
    }
    /// WHOSE WALL A POST STANDS ON, when its writer is not the wall's owner — a person's, or my own: a link to that page.
    private func wallLink(_ it: MTBoardFeedItem) -> some View {
        Button { open(it.owner.map { MTBoardWriter.peer($0) } ?? .me) } label: {
            HStack(spacing: 6) {
                Image(systemName: "text.below.photo")
                if let owner = it.owner {
                    // USER-DATA: the wall owner's name
                    Text("On \(Text(verbatim: MTBoard.nameOf(owner)).foregroundColor(Color(uiColor: .systemBlue)))'s wall")
                } else {
                    Text("On your wall").foregroundColor(Color(uiColor: .systemBlue))
                }
                Spacer(minLength: 0)
            }
            .font(.caption).foregroundColor(.secondary)
            .frame(minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    private func open(_ w: MTBoardWriter) { MTBoardOpen.go(w, page: $page) }
}

// ════════════════════════════════════════════════════════════
// THE PAGE'S PICTURES, UP AND DOWN; THE WAY OUT, TO THE SIDE (the author's word 29.09: «in the feed of posts fix how the media
// shows: scrolling up and down, to the side the way out, and all of it native, system and at once»). Measured on 2013 before
// it: a tap on a picture waited for the whole file from the node before anything rose (MTBoardMediaView.open, MTBoard.file),
// then raised the platform's viewer with that one picture alone -- nothing above or below it, its way out a pull down; a video
// rose in the system player, alone too. The platform's viewer turns its pages sideways and closes downwards, the other way
// round from the word, so the viewer is a page of the stack in the platform's own paging scroll.
// ════════════════════════════════════════════════════════════

/// WHICH PICTURE OPENED, AND ON WHICH PAGE: the post and its file, the wall it stands on, and the feed's search when the feed
/// drew it (nil -- a wall's own page).
struct MTBoardShow: Hashable {
    let pid: String
    let at: Int
    let owner: String?
    let feed: String?
    var start: String { pid + "#" + String(at) }
}

/// One screen of the viewer: a picture or a video of a post, and the wall the post stands on.
struct MTBoardShown: Identifiable {
    let post: MTBoardSeen
    let i: Int
    let wall: String?
    var id: String { post.id + "#" + String(i) }
    var media: MTBoardMedia { post.media[i] }
    var name: String { MTBoard.fileName(post.id, i, media.ext) }
    /// The file on this phone: the store's (the writer's, a keeper's, a tap's), else the copy a look brought (MTBoardLook).
    var local: URL? {
        if MontanaMediaStore.exists(name) { return MontanaMediaStore.url(name) }
        return MTBoardLook.here(post.id, i, media.ext)
    }
    /// THE PAGE IS THE ALBUM, as it is the playlist (MTBoardPlaylist, the author's word 29.09 on 2002): every picture and video of
    /// the page the post stands on, in the page's order, each post once -- the feed's under its search in the feed, the wall's on
    /// the wall; a post the page no longer holds as the finger came is an album of its own.
    @MainActor static func all(_ s: MTBoardShow) -> [MTBoardShown] {
        let board = MTBoard.shared
        let page: [(post: MTBoardSeen, wall: String?)]
        if let q = s.feed {
            page = board.feed().filter { it in MTFeedTabView.matches(it.post, wall: it.owner, q) }.map { it in (post: it.post, wall: it.owner) }
        } else {
            page = board.posts(on: s.owner).map { p in (post: p, wall: s.owner) }
        }
        let out = visual(page)
        if out.contains(where: { it in it.id == s.start }) { return out }
        let everywhere: [(post: MTBoardSeen, wall: String?)] = board.feed().map { it in (post: it.post, wall: it.owner) }
            + board.posts(on: s.owner).map { p in (post: p, wall: s.owner) }
        guard let hit = everywhere.first(where: { it in it.post.id == s.pid }) else { return out }
        return visual([hit])
    }
    @MainActor private static func visual(_ page: [(post: MTBoardSeen, wall: String?)]) -> [MTBoardShown] {
        var once = Set([String]())
        var out: [MTBoardShown] = []
        for (p, w) in page where once.insert(p.id).inserted {
            for j in p.media.indices where MTBoardMediaView.visual(p.media[j]) {
                out.append(MTBoardShown(post: p, i: j, wall: w))
            }
        }
        return out
    }
}

/// THE VIEWER: a page pushed on the stack the feed or the wall stands in, so the way out is the platform's own back -- its
/// chevron, and its swipe to the side, as from every page of the stack (on 26 from anywhere on the page, before it from the
/// edge). Its pictures and videos (MTBoardShown.all) stand one screen each in the platform's own paging scroll: up to the one
/// before, down to the next; it opens on the one tapped, in its first frame, and asks the network for nothing before it stands.
/// While a picture stands enlarged the pages hold still -- the pan is the picture's. The share is the app's one (MTShare), with
/// the file this phone holds.
struct MTBoardMediaPage: View {
    let show: MTBoardShow
    @State private var items: [MTBoardShown]
    @State private var current: String?
    @State private var zoomed = false
    @State private var placed = false

    init(show: MTBoardShow) {
        self.show = show
        _items = State(initialValue: MTBoardShown.all(show))
        _current = State(initialValue: show.start)
    }

    var body: some View {
        ScrollViewReader { reader in
            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    ForEach(items) { it in
                        MTBoardShownPage(item: it, active: current == it.id, onZoom: { z in zoomed = z })
                            .containerRelativeFrame([.horizontal, .vertical])
                            .id(it.id)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $current)
            .scrollDisabled(zoomed)
            .scrollIndicators(.hidden)
            .ignoresSafeArea()
            .onAppear {
                // THE FIRST FRAME STANDS ON THE ONE TAPPED: a position's first value does not move a scroll's first layout
                // (measured on the album's strip, 12.09) -- the reader places it as the page is born.
                guard !placed else { return }
                placed = true
                reader.scrollTo(show.start, anchor: .top)
                MontanaP2PTrace.mark("wall_show", "open pages=\(items.count) at=\(place(show.start)) in=\(show.feed == nil ? "wall" : "feed")")
            }
        }
        .background(Color.black.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)   // the picture runs under the bar, the marks stand on their own glass
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                MontanaBarMark(glyph: "square.and.arrow.up", label: "Share", action: { share() })
            }
        }
        .onChange(of: current) { _, now in
            guard let now else { return }
            MontanaP2PTrace.mark("wall_show", "page at=\(place(now)) of=\(items.count)")
        }
    }
    private func place(_ id: String) -> Int { (items.firstIndex(where: { it in it.id == id }) ?? -1) + 1 }
    /// The file of the screen looked at, read at the tap; a file not yet here (a video still coming) shares nothing yet.
    private func share() {
        guard let it = items.first(where: { x in x.id == current }), let u = it.local else { return }
        MTShare.present([u])
    }
}

/// One screen of the viewer, by its kind.
struct MTBoardShownPage: View {
    let item: MTBoardShown
    let active: Bool
    var onZoom: (Bool) -> Void
    var body: some View {
        if item.media.kind == "vid" {
            MTBoardShownVideo(item: item, active: active)
        } else {
            MTBoardShownPicture(item: item, active: active, onZoom: onZoom)
        }
    }
}

/// A screen of a picture: the picture whole, fitted, zoomed as Photos does (MTZoomImage, the system's own zoom). At once it stands
/// in the poster its post carries -- decoded already where the feed drew it -- and turns sharp from the file the moment the file
/// lies here, decoded off the main thread at the zoom's pixels and kept by its cost. The screen looked at goes the tap's own road
/// (MTBoard.file): the file comes, this phone becomes the post's peer and the download counts, as a tap on the tile did.
struct MTBoardShownPicture: View {
    let item: MTBoardShown
    let active: Bool
    var onZoom: (Bool) -> Void
    @State private var sharp: UIImage?
    @State private var poster: UIImage?
    @State private var bringing = false

    var body: some View {
        MTZoomImage(image: sharp ?? poster ?? MTBoardPoster.kept(item.media.thumb), active: active, onTap: { _ in }, onZoom: onZoom)
            .overlay { if bringing, sharp == nil { ProgressView().tint(.white) } }
            .task(id: item.id) { await draw() }
            .task(id: active) { if active { await bring() } }
    }
    /// The zoom's own pixels: a tile's longest (MTBoardImage.drawn).
    private static let longest: CGFloat = 2400
    /// A few screens of pictures at their own pixels, emptied at the door with every cache (MontanaCaches).
    private static let cache: NSCache<NSString, UIImage> = MontanaCaches.kept("wall-shown", cost: 48_000_000)
    private func draw() async {
        if await sharpen() { return }
        if poster == nil { poster = await MTBoardPoster.decoded(item.media.thumb) }
    }
    @discardableResult private func sharpen() async -> Bool {
        if sharp != nil { return true }
        guard let u = item.local else { return false }
        let key = u.path as NSString
        if let c = Self.cache.object(forKey: key) { sharp = c; return true }
        let px = Self.longest
        guard let img = await Task.detached(priority: .userInitiated, operation: {
            MTBoardImage.upright(u, kind: "img", longest: px)
        }).value else { return false }
        Self.cache.setObject(img, forKey: key, cost: Int(img.size.width * img.size.height * 4))
        sharp = img
        return true
    }
    private func bring() async {
        bringing = !MontanaMediaStore.exists(item.name)
        _ = await MTBoard.shared.file(item.post, item.i, on: item.wall)
        bringing = false
        await sharpen()
    }
}

/// A screen of a video: the platform's own player view (VideoPlayer, as a story's video) -- its controls and its scrub -- playing
/// with sound while its screen is the one looked at, resting when the screen is scrolled away; the full screen and the mini
/// window stay the one road's (VideoPresenter). A file this phone holds plays from the disk; another plays from its first pieces
/// through the file's one loader (MTStreams, shared with the feed's tile) and is kept whole by the tap's road once the loader
/// holds it all (MTBoard.file). The poster the post carries stands in it until the first frame.
struct MTBoardShownVideo: View {
    let item: MTBoardShown
    let active: Bool
    @State private var player: AVPlayer?
    @State private var poster: UIImage?
    @State private var started = false
    @State private var watch: NSKeyValueObservation?

    var body: some View {
        VideoPlayer(player: player) {
            if !started, let img = poster ?? MTBoardPoster.kept(item.media.thumb) {
                Image(uiImage: img).resizable().scaledToFit().allowsHitTesting(false)
            }
        }
        .onChange(of: active, initial: true) { _, on in if on { play() } else { player?.pause() } }
        .onDisappear { rest() }
        .task(id: item.id) { if poster == nil { poster = await MTBoardPoster.decoded(item.media.thumb) } }
    }
    private func play() {
        if player == nil {
            guard let born = Self.born(item) else { return }
            let p = AVPlayer(playerItem: born)
            watch = p.observe(\.timeControlStatus, options: [.new]) { seen, _ in
                guard seen.timeControlStatus == .playing else { return }
                DispatchQueue.main.async { started = true }
            }
            player = p
        }
        if !MontanaMediaStore.exists(item.name), MTBoardLook.here(item.post.id, item.i, item.media.ext) != nil {
            let p = item.post, i = item.i, wall = item.wall
            Task { _ = await MTBoard.shared.file(p, i, on: wall) }   // a whole copy a look left is taken, as the tap took it
        }
        MontanaAudioSession.activatePlayback()
        player?.play()
    }
    private func rest() {
        player?.pause()
        watch = nil
        player = nil
        started = false
    }
    private static func born(_ it: MTBoardShown) -> AVPlayerItem? {
        if let u = it.local { return AVPlayerItem(url: u) }
        guard let s = MTBoard.streamSource(it.post, it.i) else { return nil }
        let p = it.post, i = it.i, wall = it.wall
        let v = AVPlayerItem(asset: MTStreams.asset(s, whole: { Task { _ = await MTBoard.shared.file(p, i, on: wall) } }))
        v.preferredForwardBufferDuration = 8
        return v
    }
}
