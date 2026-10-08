import SwiftUI
import UIKit

/// THE PICTURE UNDER THE FINGER IS THE PLATFORM'S OWN SCROLL (the rule of 18.09: name the
/// mechanism iOS already carries and take it). A sticker is cut by moving and scaling the picture
/// inside a frame -- UIScrollView does both, with its own inertia, its own bounce and its own
/// two-finger zoom -- and what stands inside the frame IS the sticker: the accepted picture is
/// that view rendered, so what the person sees is what leaves, to the pixel.
final class MTStickerCanvas: ObservableObject {
    weak var scroll: UIScrollView?

    /// What stands inside the frame right now, on a transparent ground, at the sticker's canvas.
    func png(side: CGFloat = MontanaStickerCut.side) -> Data? {
        guard let sv = scroll, sv.bounds.width > 1 else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = max(1, side / sv.bounds.width)
        format.opaque = false
        let shot = UIGraphicsImageRenderer(bounds: sv.bounds, format: format).image { ctx in
            sv.layer.render(in: ctx.cgContext)
        }
        return MontanaStickerCut.encode(MontanaStickerCut.fit(shot))
    }
}

struct MTZoomPicture: UIViewRepresentable {
    let image: UIImage
    let canvas: MTStickerCanvas

    func makeCoordinator() -> Coordinator { Coordinator(image: image) }

    func makeUIView(context: Context) -> UIScrollView {
        let sv = UIScrollView()
        sv.delegate = context.coordinator
        sv.minimumZoomScale = 1
        sv.maximumZoomScale = 5
        sv.bouncesZoom = true
        sv.showsHorizontalScrollIndicator = false
        sv.showsVerticalScrollIndicator = false
        sv.backgroundColor = .clear
        sv.clipsToBounds = true
        let iv = UIImageView(image: image)
        iv.contentMode = .scaleAspectFit
        iv.isUserInteractionEnabled = true
        sv.addSubview(iv)
        context.coordinator.picture = iv
        canvas.scroll = sv
        return sv
    }

    func updateUIView(_ sv: UIScrollView, context: Context) {
        canvas.scroll = sv
        context.coordinator.show(image, in: sv)
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        var picture: UIImageView?
        private var shown: UIImage
        private var lastBox: CGSize = .zero

        init(image: UIImage) { shown = image }

        func show(_ image: UIImage, in sv: UIScrollView) {
            let box = sv.bounds.size
            guard box.width > 1, let iv = picture else { return }
            let fresh = image !== shown
            guard fresh || box != lastBox else { return }
            shown = image
            lastBox = box
            iv.image = image
            let w = max(image.size.width, 1), h = max(image.size.height, 1)
            let k = min(box.width / w, box.height / h)
            iv.frame = CGRect(origin: .zero, size: CGSize(width: w * k, height: h * k))
            sv.contentSize = iv.frame.size
            sv.zoomScale = 1
            centre(sv)
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { picture }
        func scrollViewDidZoom(_ scrollView: UIScrollView) { centre(scrollView) }

        /// The picture sits in the middle of the frame while it is smaller than the frame -- the
        /// platform's own way of centring a zoomed view, by its insets.
        private func centre(_ sv: UIScrollView) {
            guard let iv = picture else { return }
            let x = max(0, (sv.bounds.width - iv.frame.width) / 2)
            let y = max(0, (sv.bounds.height - iv.frame.height) / 2)
            sv.contentInset = UIEdgeInsets(top: y, left: x, bottom: y, right: x)
        }
    }
}

/// THE STICKER EDITOR (the author's word 22.09, his own screenshots). The picture stands in the
/// frame; the finger moves and scales it; beside it, when the platform found a subject, stand two
/// miniatures -- the whole picture and its subject -- and the finger points at the one that rides.
/// Our cross leaves at the top left, our checkmark keeps at the right: no button here wears a word.
struct MontanaStickerEditor: View {
    let source: UIImage
    var onDone: (Data) -> Void
    var onCancel: () -> Void

    @StateObject private var canvas = MTStickerCanvas()
    @State private var cut: UIImage?
    @State private var useCut = false
    @State private var asked = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                MontanaCloseMark { onCancel() }
                Spacer()
                MontanaDoneMark {
                    if let data = canvas.png() { onDone(data) } else { onCancel() }
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 6)

            GeometryReader { g in
                let side = max(120, min(g.size.width, g.size.height) - 24)
                MTZoomPicture(image: useCut ? (cut ?? source) : source, canvas: canvas)
                    .frame(width: side, height: side)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .overlay { RoundedRectangle(cornerRadius: 20).stroke(Color.white.opacity(0.2), lineWidth: 1) }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            if let cut {
                HStack(spacing: 16) {
                    face(source, chosen: !useCut) { useCut = false }
                    face(cut, chosen: useCut) { useCut = true }
                }
                .padding(.bottom, 26)
            }
        }
        .background(Color.black.ignoresSafeArea())
        .onAppear { askForSubject() }
    }

    /// The miniature of one face of the picture: the chosen one wears the ring. A miniature, never
    /// a word (the rule of 22.09), on the platform's least target.
    private func face(_ image: UIImage, chosen: Bool, tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            Image(uiImage: image).resizable().aspectRatio(contentMode: .fit).padding(6)
                .frame(width: 66, height: 66)
                .background(Color(white: 0.14), in: RoundedRectangle(cornerRadius: 14))
                .overlay {
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.white.opacity(chosen ? 0.9 : 0.15), lineWidth: chosen ? 2 : 1)
                }
                .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    /// The subject is lifted off the screen's thread, once: the editor opens at the first frame and
    /// the second miniature appears when the platform has answered.
    private func askForSubject() {
        guard !asked else { return }
        asked = true
        let picture = source
        DispatchQueue.global(qos: .userInitiated).async {
            let found = MontanaStickerCut.subject(of: picture)
            DispatchQueue.main.async {
                guard let found else { return }
                cut = found
                useCut = true   // the subject is what the person came for; the whole picture is one touch away
            }
        }
    }
}

/// A SET AS A PAGE (the author's word 22.09, his own screenshot): the stickers as miniatures four
/// in a row. A tap sends one into the conversation, a hold drops one, and the red row at the bottom
/// empties the set behind the platform's own question. Our cross stands at the top left.
///
/// The page shows ANY set: this phone's own, or one taken from another person. A set we have been
/// told about but do not hold yet asks its giver for it -- the hand that passed the link or the
/// sticker -- and fills in as the pages land. Nobody else is asked: the link carries no address.
struct MontanaStickerSetPage: View {
    /// The set to show. Empty means this phone's own.
    var pack: String = ""
    var onPick: (String) -> Void
    var onClose: () -> Void

    @ObservedObject private var book = MontanaStickerBook.shared
    @State private var asking = false
    @State private var asked = false

    private var isMine: Bool { pack.isEmpty || pack == book.mineId }
    private var names: [String] { isMine ? book.names : (book.pack(pack)?.names ?? []) }
    private var title: String { isMine ? "Montana" : (book.pack(pack)?.title ?? "Montana") }
    private var waiting: Int {
        guard !isMine, let p = book.pack(pack) else { return 0 }
        return max(0, p.expected - p.names.count)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                MontanaCloseMark { onClose() }
                Spacer()
                Text(verbatim: title)   // USER-DATA: the set's own title, as its owner wrote it
                    .font(.system(size: 17, weight: .semibold)).foregroundColor(.white)
                Spacer()
                Button {
                    UIPasteboard.general.string = MontanaStickerPack.link(id: isMine ? book.mineId : pack, title: title)
                    MontanaTrace.mark("sticker_link", "copied")
                } label: {
                    Image(systemName: "link")
                        .font(.system(size: 17))
                        .foregroundColor(.white.opacity(0.85))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)

            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 12) {
                    ForEach(names, id: \.self) { n in
                        Button { onPick(n) } label: {
                            Group {
                                if let ui = docImage(n) {
                                    Image(uiImage: ui).resizable().aspectRatio(contentMode: .fit)
                                } else {
                                    Color.clear
                                }
                            }
                            .frame(height: 78)
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            if isMine {
                                Button(role: .destructive) { book.forget(n) } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                    // What has not arrived yet stands as an empty place, not as a word: the set is
                    // filling, and the eye sees how much of it is still on the way.
                    ForEach(0..<waiting, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.white.opacity(0.05))
                            .frame(height: 78)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 14)
            }

            if !names.isEmpty {
                MTMenuDivider()
                MTMenuRow(title: isMine ? "Delete all" : "Remove set", icon: "trash", destructive: true) { asking = true }
                    .padding(.bottom, 8)
            }
        }
        .background(Color(white: 0.08).ignoresSafeArea())
        .onAppear { askGiver() }
        .confirmationDialog("Delete all", isPresented: $asking, titleVisibility: .hidden) {
            Button("Delete all", role: .destructive) {
                if isMine {
                    for n in book.names { book.forget(n) }
                } else {
                    book.drop(pack: pack)
                    onClose()
                }
            }
        }
    }

    /// A set we do not hold is asked of the one who gave it -- once per opening.
    private func askGiver() {
        guard !isMine, !asked else { return }
        asked = true
        guard waiting > 0 || names.isEmpty, let giver = book.giver(of: pack), !giver.isEmpty else { return }
        MontanaStickerWire.ask(pack: pack, from: giver, chat: giver)
    }
}
