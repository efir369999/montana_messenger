import SwiftUI
import MessageUI
import UIKit

// ════════════════════════════════════════════════════════════
// SAFETY (App Store Guideline 1.2, the author's word 15.09): the terms a person agrees to
// before the first word, the filter over objectionable words, the report of a letter or a
// person, the block that is enforced on every road, and a real way to reach us. One owner
// for the facts ([C-1]); the screens read it, the receive path and the push extension obey it.
// ════════════════════════════════════════════════════════════
enum MontanaSafety {
    /// The version of the terms the person agreed to; a new version asks anew.
    static let termsVersion = 1
    // ONE address for now (the author's word 15.09): questions and reports go to the contact
    // mailbox the review knows; two names below, one mailbox behind them.
    static let contactMail = "contact@montana.quest"
    static let abuseMail = contactMail
    static let supportMail = contactMail
    static let site = "https://montana.quest"
    static let privacy = site + "/privacy/"   // the policy on the site, in the languages the site speaks
    static var termsAccepted: Bool {
        UserDefaults.standard.integer(forKey: "termsAcceptedVersion") >= termsVersion
    }
    static func acceptTerms() {
        UserDefaults.standard.set(termsVersion, forKey: "termsAcceptedVersion")
        MontanaTrace.mark("terms", "accepted v=\(termsVersion)")
    }
    /// THE BARRED ADDRESSES — the network's answer to reports: an address the operators barred
    /// is refused by every install like a blocked one (the receive path, the push extension).
    /// The node itself cannot bar anyone — it sees labels, never identities (the anonymity of
    /// stage 25) — so the bar is carried down to the phones, where identities are known.
    static var barred: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: "barredPeers") ?? [])
    }
    static func setBarred(_ list: [String]) {
        let clean = list.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard Set(clean) != barred else { return }
        UserDefaults.standard.set(clean, forKey: "barredPeers")
        MontanaKeychain.set("barredPeers", (try? JSONEncoder().encode(clean)) ?? Data())   // the push extension refuses them too
        MontanaTrace.mark("barred", "n=\(clean.count)")
    }
    /// A mail link for the phones that keep their mail in another app.
    static func mailto(_ to: String, subject: String, body: String) -> URL? {
        var c = URLComponents(); c.scheme = "mailto"; c.path = to
        c.queryItems = [URLQueryItem(name: "subject", value: subject), URLQueryItem(name: "body", value: body)]
        return c.url
    }
    /// The filter over objectionable words is ON until the person turns it off.
    static var filterOn: Bool {
        get { UserDefaults.standard.object(forKey: "objectionableFilterOn") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "objectionableFilterOn") }
    }
    /// The push extension refuses the barred and filters by the keychain's word alone: when the store changed
    /// under it (a copy laid, 23.09) both are written again from the store.
    static func mirror() {
        MontanaKeychain.set("barredPeers", (try? JSONEncoder().encode(Array(barred).sorted())) ?? Data())
        MontanaKeychain.set("objectionableFilterOn", Data([filterOn ? 1 : 0]))
    }
}

/// THE FILTER'S FOLD IS OPENED FOR THE LETTER, NOT FOR ONE DRAWING OF IT (the author's word 24.09: «what the
/// filter hid did not show again on the iPhone -- it must always work and show on the tap»). The opening lived
/// in the bubble's own state, and a letter is drawn anew more than once: the menu's own copy of the letter, a
/// cell the feed scrolled away and gave back -- each new drawing began folded, so a letter the person had
/// opened stood hidden again. The person's tap is written here, by the letter's name, for the life of the
/// app, and every drawing of the letter reads it. A launch folds again.
final class MTFilterFold: ObservableObject {
    static let shared = MTFilterFold()
    @Published private(set) var opened: Set<MID> = []
    func open(_ id: MID) {
        guard !opened.contains(id) else { return }
        opened.insert(id)
        MontanaTrace.mark("filter_open", "the letter unfolded by the person's tap")
    }
}

/// THE TERMS (EULA) a person agrees to before the first word. Plain sentences, the platform's
/// own list style; the same text is reachable from Settings at any time.
struct MontanaTermsView: View {
    var gate = false                    // true = the first screen: no way past without agreeing
    var onAgree: () -> Void = {}
    var body: some View {
        VStack(spacing: 0) {
            List {
                Section {
                    Text("Montana is a messenger between people who chose to talk to each other. Every conversation is encrypted end to end; nobody but its two sides can read it.")
                    Text("By using Montana you agree to these terms.")
                }.listRowBackground(MTGlassRowPlate()).foregroundColor(.white)
                Section("No tolerance for abuse") {
                    Text("There is no tolerance for objectionable content or abusive users: threats, harassment, hate speech, sexual content involving minors, spam and any content that breaks the law.")
                    Text("You must be 18 or older to use Montana.")
                    Text("A person who sends such content or abuses others is barred from Montana's relays and doors.")
                }.listRowBackground(MTGlassRowPlate()).foregroundColor(.white)
                Section("Your tools") {
                    Text("Block: a blocked person can no longer reach you — their letters are refused on every road and never shown.")
                    Text("Report: any letter or person can be reported from its menu. Reports are reviewed within 24 hours; offending content is removed and the offender is barred.")
                    Text("Filter: letters carrying objectionable words are folded by default and unfold only by your tap. The filter is yours to keep or turn off in Privacy.")
                    Text("Delete: any letter can be removed from your feed at once — for you, or for everyone.")
                }.listRowBackground(MTGlassRowPlate()).foregroundColor(.white)
                Section("Reach us") {
                    Link(destination: URL(string: "mailto:\(MontanaSafety.abuseMail)")!) {
                        Label { Text(verbatim: MontanaSafety.abuseMail) } icon: { Image(systemName: "envelope") }   // USER-DATA: an address
                    }
                    Link(destination: URL(string: MontanaSafety.site)!) {
                        Label { Text(verbatim: MontanaSafety.site) } icon: { Image(systemName: "globe") }   // USER-DATA: an address
                    }
                }.listRowBackground(MTGlassRowPlate()).foregroundColor(Color.accentColor)
            }
            .scrollContentBackground(.hidden)
            if gate {
                // THE PATH'S LAST ACT BEFORE THE CHATS IS A DOOR (the author's word 29.09, 23:25: the buttons in the new style of our
                // OS, every page up to the chats): the path's one plate (MTLoginDoorStyle), the main act on the platform's blue glass.
                Button(action: onAgree) { Text("I agree") }
                    .buttonStyle(MTLoginDoorStyle(tint: MontanaOctagon.platformBlue))
                    .padding(.horizontal, 20).padding(.vertical, 12)
            }
        }
        .montanaPageGround()   // my page's ground, as the drawer and my page wear it (25.09)
        .navigationTitle("Terms of Use").navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
    }
}

/// The first screen after the identity, before the first word: the terms and one button.
struct MontanaTermsGate: View {
    var onAgree: () -> Void
    var body: some View {
        NavigationStack { MontanaTermsView(gate: true, onAgree: onAgree) }
    }
}

/// REPORTING a letter or a person: a reason, then a mail to the abuse desk with what is
/// needed to act — the reporter's own address, the reported one, the reason, and the
/// letter's text when a letter is reported. The mail leaves by the system composer; where
/// no mail account stands, the address is offered to copy.
struct MontanaReport: Identifiable {
    let id = UUID()
    let peer: String          // the reported person's address
    let peerName: String
    let text: String          // the letter's words, or empty for a person
    let mid: String
}

struct MontanaReportSheet: View {
    let report: MontanaReport
    var onBlock: () -> Void
    /// The block is offered for a person this phone knows (25.09): a post whose writer a wall never named is reported through
    /// the wall that carried it, and nobody is blocked for another's words.
    var offersBlock = true
    @Environment(\.dismiss) private var dismiss
    @State private var reason: LocalizedStringKey = "Spam"
    @State private var reasonKey = "spam"
    @State private var composing = false
    @State private var copied = false
    @State private var blockToo = true
    private let reasons: [(String, LocalizedStringKey)] = [("spam", "Spam"), ("abuse", "Harassment or threats"), ("hate", "Hate speech"), ("illegal", "Illegal content"), ("other", "Other")]
    private var body_: String {
        var s = "Report (\(reasonKey))\nReporter: \(MontanaPhoneNode.myRef())\nReported: \(report.peer)"
        if !report.peerName.isEmpty { s += " (\(report.peerName))" }
        if !report.mid.isEmpty { s += "\nLetter: \(report.mid)" }
        if !report.text.isEmpty { s += "\n\n---\n\(report.text)\n---" }
        s += "\n\nBuild: \(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "")"
        return s
    }
    var body: some View {
        NavigationStack {
            List {
                Section("Reason") {
                    ForEach(reasons, id: \.0) { r in
                        Button {
                            reasonKey = r.0; reason = r.1
                        } label: {
                            HStack {
                                Text(r.1).foregroundColor(.white)
                                Spacer()
                                if reasonKey == r.0 { Image(systemName: "checkmark").foregroundColor(Color.accentColor) }
                            }
                            .contentShape(Rectangle())   // the whole row is the target, not only its words (22.09)
                        }
                    }
                }.listRowBackground(MTGlassRowPlate())
                if !report.text.isEmpty {
                    Section("Reported letter") {
                        Text(verbatim: report.text).foregroundColor(.gray).lineLimit(6)   // USER-DATA: the letter
                    }.listRowBackground(MTGlassRowPlate())
                }
                if offersBlock {
                    Section {
                        Toggle("Block this person too", isOn: $blockToo).foregroundColor(.white)
                    }.listRowBackground(MTGlassRowPlate())
                }
                Section {
                    Button {
                        MontanaTrace.mark("report", "reason=\(reasonKey) letter=\(report.mid.isEmpty ? 0 : 1)")
                        if blockToo && offersBlock { onBlock() }
                        if MFMailComposeViewController.canSendMail() { composing = true }
                        else if let u = MontanaSafety.mailto(MontanaSafety.abuseMail, subject: "Montana report (\(reasonKey))", body: body_),
                                UIApplication.shared.canOpenURL(u) {
                            UIApplication.shared.open(u); dismiss()
                        } else {
                            UIPasteboard.general.string = "\(MontanaSafety.abuseMail)\n\n\(body_)"
                            copied = true
                        }
                    } label: { Text("Send report").foregroundColor(.accentColor) }
                    Text("Reports go to \(MontanaSafety.abuseMail) and are reviewed within 24 hours.")
                        .font(.footnote).foregroundColor(.gray)
                }.listRowBackground(MTGlassRowPlate())
            }
            .scrollContentBackground(.hidden).montanaPageGround()   // my page's ground, as every page wears it (26.09)
            .navigationTitle("Report").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { MontanaCloseMark { dismiss() } } }
            .sheet(isPresented: $composing, onDismiss: { dismiss() }) {
                MTMailComposer(to: MontanaSafety.abuseMail, subject: "Montana report (\(reasonKey))", body: body_)
            }
            .alert("No mail account on this phone. The report and our address are copied — paste them into any mail.", isPresented: $copied) {
                Button("OK") { dismiss() }
            }
        }
        .preferredColorScheme(.dark)
    }
}

/// The system mail composer, as it is.
struct MTMailComposer: UIViewControllerRepresentable {
    let to: String; let subject: String; let body: String
    @Environment(\.dismiss) private var dismiss
    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let vc = MFMailComposeViewController()
        vc.setToRecipients([to]); vc.setSubject(subject); vc.setMessageBody(body, isHTML: false)
        vc.mailComposeDelegate = context.coordinator
        return vc
    }
    func updateUIViewController(_ vc: MFMailComposeViewController, context: Context) {}
    func makeCoordinator() -> Coord { Coord(dismiss: dismiss) }
    final class Coord: NSObject, MFMailComposeViewControllerDelegate {
        let dismiss: DismissAction
        init(dismiss: DismissAction) { self.dismiss = dismiss }
        func mailComposeController(_ c: MFMailComposeViewController, didFinishWith r: MFMailComposeResult, error: Error?) {
            MontanaTrace.mark("report", "mail result=\(r.rawValue)")
            dismiss()
        }
    }
}

/// THE BLOCKED LIST (Settings → Privacy): every blocked person, one tap to unblock.
struct MontanaBlockedView: View {
    @EnvironmentObject var store: ChatStore
    var body: some View {
        List {
            if store.blockedChats.isEmpty {
                Text("Nobody is blocked.").foregroundColor(.gray).listRowBackground(MTGlassRowPlate())
            } else {
                ForEach(store.blockedChats.sorted(), id: \.self) { name in
                    HStack {
                        Text(verbatim: store.displayName(for: name)).foregroundColor(.white).lineLimit(1)   // USER-DATA: a person's name
                        Spacer()
                        Button("Unblock") { store.toggleBlocked(name) }.foregroundColor(Color.accentColor)
                    }
                    .listRowBackground(MTGlassRowPlate())
                }
            }
        }
        .scrollContentBackground(.hidden).montanaPageGround()   // my page's ground, as the drawer and my page wear it (25.09)
        .navigationTitle("Blocked users").navigationBarTitleDisplayMode(.inline)
    }
}
