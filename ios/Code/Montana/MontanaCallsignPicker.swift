import SwiftUI

// Choosing a call sign: the same hundred and twenty-eight rows the set ships, read in the language
// of this device. A person who claimed no name is given one; here they may take another instead —
// the choice is theirs and it stays on the device, exactly like the name they would have typed.
struct MontanaCallsignPicker: View {
    var onMaking = false   // opened on the making of an identity: the path's black ground, every word white (word 18949)
    @AppStorage("userName") private var name: String = ""
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var rows: [String] { MontanaCallsign.all() }
    private var shown: [String] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return q.isEmpty ? rows : rows.filter { $0.lowercased().contains(q) }
    }

    var body: some View {
        List {
            ForEach(shown, id: \.self) { row in
                Button {
                    name = row
                    MontanaTrace.mark("callsign_chosen", "len=\(row.count)")
                    E2E.shared.broadcastName()      // peers learn the new name the same way as always
                    dismiss()
                } label: {
                    HStack {
                        // USER-DATA: a callsign table row, not interface text.
                        Text(verbatim: row).foregroundColor(onMaking ? Color.white : Color.primary)
                        Spacer()
                        if row == name { Image(systemName: "checkmark").foregroundColor(Color.accentColor) }
                    }
                    .contentShape(Rectangle())   // the whole row is the target, not only its words (22.09)
                }
            }
        }
        .scrollContentBackground(onMaking ? .hidden : .automatic)
        .background(onMaking ? Color.black : Color.clear)
        .searchable(text: $query)
        .navigationTitle("Call sign")
        .navigationBarTitleDisplayMode(.inline)
    }
}
