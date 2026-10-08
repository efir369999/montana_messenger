import SwiftUI
import PhotosUI

/// THE CHANNEL IS BORN IN THREE STEPS (the author's words 05.10.2026 19:0x MSK: «3. Channel -- see the mechanics in the reference
/// tree»; 19:1x «real delivery to a channel from the phone»): what a channel is, then its face, name and description, then the
/// subscribers, each chosen by a tick. A channel is a group whose owner alone posts; its posts ride the pipe of each subscriber
/// from this phone, so only a person this phone holds a pipe with can subscribe (MTGroupPickStep.reachable).
struct MTChannelIntroStep: View {
    @Environment(\.dismiss) private var dismiss
    var onCreate: (String, String, Data, [Chat]) -> Void
    @State private var naming = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Spacer()
                Image(systemName: "megaphone.fill").font(.system(size: 64)).foregroundColor(.white)
                Text("What is a channel?").font(.title2.bold())
                VStack(spacing: 10) {
                    Text("A channel sends your posts to the people you choose.")
                    Text("Only you post; subscribers read.")
                    Text("Every post goes phone to phone, over the pipe you hold with each subscriber.")
                }
                .font(.body).foregroundColor(.secondary).multilineTextAlignment(.center)
                Spacer()
                Spacer()
            }
            .padding(.horizontal, 32)
            .frame(maxWidth: .infinity)
            .montanaPageGround()
            .navigationTitle("New Channel").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { MontanaCloseMark { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { MontanaDoneMark { naming = true } }
            }
            .navigationDestination(isPresented: $naming) {
                MTChannelInfoStep { title, about, face, subscribers in
                    onCreate(title, about, face, subscribers)
                    dismiss()
                }
            }
        }
    }
}

/// The second step: the channel's face, name and description.
struct MTChannelInfoStep: View {
    var onCreate: (String, String, Data, [Chat]) -> Void
    @State private var name = ""
    @State private var about = ""
    @State private var face = Data()
    @State private var choosing = false
    @FocusState private var typing: Bool

    private var title: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    MTFacePicker(face: $face)
                    TextField("Channel name", text: $name).focused($typing)
                }
            }
            .listRowBackground(MTGlassRowPlate())
            Section {
                TextField("Description", text: $about, axis: .vertical).lineLimit(1...6)
            } footer: {
                Text("You can add a description to your channel.")
            }
            .listRowBackground(MTGlassRowPlate())
        }
        .scrollContentBackground(.hidden).montanaPageGround()
        .navigationTitle("New Channel").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                MontanaDoneMark { choosing = true }.disabled(title.isEmpty).opacity(title.isEmpty ? 0.4 : 1)
            }
        }
        .onAppear { typing = true }
        .navigationDestination(isPresented: $choosing) {
            MTChannelSubscribersStep { subscribers in
                onCreate(title, about.trimmingCharacters(in: .whitespacesAndNewlines), face, subscribers)
            }
        }
    }
}

/// The third step: the subscribers, each chosen by a tick among the people this phone holds a pipe with.
struct MTChannelSubscribersStep: View {
    @EnvironmentObject private var store: ChatStore
    var onCreate: ([Chat]) -> Void
    @State private var chosen: [String] = []
    @State private var query = ""

    private var people: [Chat] { MTGroupPickStep.reachable(store) }
    private var shown: [Chat] {
        let q = query.trimmingCharacters(in: .whitespaces)
        return q.isEmpty ? people : people.filter { store.title(for: $0).localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        List {
            Section {
                ForEach(shown) { c in
                    Button { toggle(c.convRef) } label: { MTPickRow(chat: c, on: chosen.contains(c.convRef)) }
                }
            } footer: {
                Text("A post rides the pipe of each person, so only the people you write with are listed.")
            }
            .listRowBackground(MTGlassRowPlate())
        }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always))
        .scrollContentBackground(.hidden).montanaPageGround()
        .navigationTitle("Add subscribers").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                MontanaDoneMark { onCreate(chosen.compactMap { ref in people.first { $0.convRef == ref } }) }
                    .disabled(chosen.isEmpty).opacity(chosen.isEmpty ? 0.4 : 1)
            }
        }
    }

    private func toggle(_ ref: String) {
        if let i = chosen.firstIndex(of: ref) { chosen.remove(at: i) } else { chosen.append(ref) }
    }
}

/// A person in a list of choice -- the face, the name, the tick; the whole row is the target, not only its words (22.09).
struct MTPickRow: View {
    @EnvironmentObject private var store: ChatStore
    let chat: Chat
    let on: Bool

    var body: some View {
        HStack(spacing: 12) {
            MTChatAvatar(chat: chat, size: 40)
            Text(verbatim: store.title(for: chat)).foregroundColor(.primary)   // USER-DATA: a person's name
            Spacer()
            Image(systemName: on ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundColor(on ? .white : .secondary)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}

/// The face of a group or a channel: the platform's photo picker in a circle, the picture brought to the avatar's size.
struct MTFacePicker: View {
    @Binding var face: Data
    @State private var pick: PhotosPickerItem?

    var body: some View {
        PhotosPicker(selection: $pick, matching: .images) {
            Group {
                if let ui = UIImage(data: face) {
                    Image(uiImage: ui).resizable().scaledToFill()
                } else {
                    Circle().fill(Color(.tertiarySystemFill))
                        .overlay(Image(systemName: "camera.fill").font(.title3).foregroundColor(.white))
                }
            }
            .frame(width: 60, height: 60).clipShape(Circle())
        }
        .onChange(of: pick) { _, item in
            Task {
                if let data = try? await item?.loadTransferable(type: Data.self), let ui = UIImage(data: data) {
                    face = ui.avatarResized(1080).jpegData(compressionQuality: 0.85) ?? data
                }
            }
        }
    }
}
