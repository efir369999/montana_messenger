import AVFoundation
import Foundation
import Speech

/// THE VOICE READ AS TEXT, ON THIS PHONE (the author's word 21.10.2026 09:15 UTC: «voice transcription natively, by the system:
/// iOS 26+ SpeechAnalyzer, the best way; before 26 SFSpeechRecognizer -- the URL request, on the device when it can, punctuation,
/// the contacts' names and the chat's frequent words as context»). The platform's own recogniser reads the voice's file where it
/// lies. ON THE DEVICE ONLY: the server recogniser would carry a private voice to a third party, and privacy has no degrees -- a
/// phone that cannot read the language itself says so and sends nothing. The words live in memory beside the voice's name (a
/// name never changes while the letter lives) and die with the process: a deleted chat leaves no text of its voices on disk.
/// One owner: the bubble asks, this reads and answers.
@MainActor
final class MTVoiceTranscript: ObservableObject {
    enum Reading: Equatable {
        case working
        case text(String)
        case silent        // the recogniser heard no words
        case refused       // the person said no to speech recognition
        case unsupported   // this phone cannot read this language on itself
    }

    static let shared = MTVoiceTranscript()
    @Published private(set) var readings: [String: Reading] = [:]
    private var order: [String] = []
    private static let kept = 400   // BOUND-OK: the readings of one run, the oldest goes first

    /// The glyph is drawn only where a reading can happen on the device at all.
    static let canRead: Bool = {
        if #available(iOS 26.0, *), SpeechTranscriber.isAvailable { return true }
        return (SFSpeechRecognizer(locale: MTLanguage.locale) ?? SFSpeechRecognizer())?.supportsOnDeviceRecognition ?? false
    }()

    /// Reads the voice once; a finished text is kept, a reading that failed is tried again on the next ask.
    func read(_ file: String, hints: [String]) {
        switch readings[file] {
        case .working?, .text?: return
        default: break
        }
        readings[file] = .working
        let started = Date()
        Task {
            let url = await Task.detached(priority: .userInitiated) { MontanaMediaVault.playableURL(file) }.value
            let got: Reading
            if let url { got = await Self.recognise(url, hints: hints) } else { got = .silent }
            self.keep(file, got)
            // never the words themselves: the diary leaves the phone
            MontanaTrace.mark("voice_text", "\(Self.word(got)) ms=\(Int(Date().timeIntervalSince(started) * 1000)) hints=\(hints.count)")
        }
    }

    private func keep(_ file: String, _ r: Reading) {
        readings[file] = r
        order.removeAll { $0 == file }
        order.append(file)
        while order.count > Self.kept { readings[order.removeFirst()] = nil }
    }

    private static func word(_ r: Reading) -> String {
        switch r {
        case .working: return "working"
        case .text(let t): return "text chars=\(t.count)"
        case .silent: return "silent"
        case .refused: return "refused"
        case .unsupported: return "unsupported"
        }
    }

    /// The context the recogniser is given: the people's names, whole and by word, then the chat's own frequent words -- at most a
    /// hundred, as the platform advises.
    nonisolated static func hints(names: [String], rows: [Message]) -> [String] {
        var out: [String] = []
        var seen = Set<String>()
        func put(_ w: String) {
            let k = w.lowercased()
            if !k.isEmpty, seen.insert(k).inserted { out.append(w) }
        }
        for n in names {
            let whole = n.trimmingCharacters(in: .whitespacesAndNewlines)
            put(whole)
            for part in whole.split(whereSeparator: { !$0.isLetter }) where part.count >= 2 { put(String(part)) }
        }
        var count: [String: Int] = [:]
        for m in rows.suffix(500) where !m.text.isEmpty {
            for w in m.text.split(whereSeparator: { !$0.isLetter }) where w.count >= 4 { count[w.lowercased(), default: 0] += 1 }
        }
        let frequent = count.filter { $0.value >= 2 }
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
        for (w, _) in frequent where out.count < 100 { put(w) }
        return Array(out.prefix(100))
    }

    nonisolated private static func recognise(_ url: URL, hints: [String]) async -> Reading {
        guard await allowed() else { return .refused }
        if #available(iOS 26.0, *), SpeechTranscriber.isAvailable, let r = await analyse(url, hints: hints) { return r }
        return await recogniseBefore26(url, hints: hints)
    }

    nonisolated private static func allowed() async -> Bool {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: return true
        case .notDetermined:
            return await withCheckedContinuation { c in
                SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0 == .authorized) }
            }
        default: return false
        }
    }

    /// iOS 26: SpeechAnalyzer with the transcriber module, the language's model installed by the system on first use. Nil when
    /// the language has no model here -- the older recogniser is asked then.
    @available(iOS 26.0, *)
    nonisolated private static func analyse(_ url: URL, hints: [String]) async -> Reading? {
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: MTLanguage.locale) else { return nil }
        let transcriber = SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [], attributeOptions: [])
        do {
            if let install = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                try await install.downloadAndInstall()
            }
            let analyzer = SpeechAnalyzer(modules: [transcriber])
            if !hints.isEmpty {
                let context = AnalysisContext()
                context.contextualStrings[.general] = hints
                try await analyzer.setContext(context)
            }
            let audio = try AVAudioFile(forReading: url)
            async let heard = transcriber.results.reduce(into: "") { all, r in all += String(r.text.characters) }
            if let end = try await analyzer.analyzeSequence(from: audio) {
                try await analyzer.finalizeAndFinish(through: end)
            } else {
                await analyzer.cancelAndFinishNow()
            }
            let text = try await heard.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? .silent : .text(text)
        } catch {
            return nil
        }
    }

    /// Before iOS 26: the URL request on the device, with punctuation and the context.
    nonisolated private static func recogniseBefore26(_ url: URL, hints: [String]) async -> Reading {
        guard let recogniser = SFSpeechRecognizer(locale: MTLanguage.locale) ?? SFSpeechRecognizer(),
              recogniser.supportsOnDeviceRecognition else { return .unsupported }
        let ask = SFSpeechURLRecognitionRequest(url: url)
        ask.requiresOnDeviceRecognition = true
        ask.addsPunctuation = true
        ask.contextualStrings = hints
        ask.shouldReportPartialResults = false
        let once = MTOnce()
        return await withCheckedContinuation { c in
            _ = recogniser.recognitionTask(with: ask) { result, error in
                _ = recogniser   // the recogniser lives until its answer
                if let result, result.isFinal, once.take() {
                    let text = result.bestTranscription.formattedString.trimmingCharacters(in: .whitespacesAndNewlines)
                    c.resume(returning: text.isEmpty ? .silent : .text(text))
                } else if error != nil, once.take() {
                    c.resume(returning: .silent)
                }
            }
        }
    }
}

/// One answer per continuation: the recogniser may call back after its final result with an error.
private final class MTOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var taken = false
    func take() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if taken { return false }
        taken = true
        return true
    }
}
