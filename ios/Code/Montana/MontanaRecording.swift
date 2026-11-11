//
//  MontanaRecording.swift
//  Montana — a Montana messenger
//
//  ONE STATE OF A RECORDING, ONE OWNER (the author's word 19.09, the reference's model). The
//  tape's truth used to live in three places — four flags of the bar's button, the parent's
//  «recording» flag and the crown's mirror — and every place they disagreed was a defect of its
//  own: a lock taken two milliseconds after the start met a stale flag and was lost (14:45:07),
//  a locked tape's arrow was drawn in one window and caught in another. Here the recording is a
//  value: idle → recording(kind) → locked(kind) → idle. The button, the crown and the bar only
//  ASK this machine (begin / lock / send / cancel / pause) and DRAW from it; nobody keeps a copy.
//  Every transition is one diary line, rec_state, and every tape has a number: a verdict born
//  under an earlier tape (the system's late lock, a stale callback) is refused by that number.
//

import SwiftUI
import Combine
import UIKit

@MainActor
final class MontanaRecording: ObservableObject {
    enum Kind: String { case voice, note }
    enum Phase: Equatable {
        case idle
        case recording(Kind)
        case locked(Kind)
    }

    let voice = VoiceRecorder()
    let note = MontanaVideoNoteCamera()
    @Published private(set) var phase: Phase = .idle
    /// Grows on every begin; a request naming an older tape is refused.
    private(set) var tapeId = 0
    /// The voice tape's road out: the screen seals it into a letter (sendVoice). The note's road
    /// is its own `finished` publisher — one road per kind, as before.
    var voiceSent: () -> Void = {}
    /// The note's road out — the SAME shape as the voice's (21.09, the critic): one closure, called
    /// once per finished tape by this owner. It used to be a `.onReceive` on the camera's published
    /// `finished` inside the compose bar — a VALUE, not an event: every rebuilt bar (the keyboard
    /// rider re-hosts it, the page re-appears after the hold window) subscribed anew and was handed
    /// the standing value again. Measured 21.09 17:36 and 17:42 (iPhone 15 Pro Max, 1829): one
    /// `rec_state →idle` per tape, two `compress START` — the second exactly at the chat's onAppear;
    /// every chunk uploaded twice, and a second row born for the same file, red «resend» for ever.
    var noteSent: (String) -> Void = { _ in }
    private var noteConsumed: String? = nil
    private var bag: [AnyCancellable] = []

    init() {
        voice.onFailure = { [weak self] in
            guard let self, self.kind == .voice else { return }
            self.cancel(why: "voice-start-failed")
        }
        // The tape's readings (levels, seconds, pause) are the recorders' own; the screen watches
        // this one object, so their changes are handed on.
        voice.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &bag)
        note.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &bag)
        note.$live.dropFirst().filter { !$0 }.sink { [weak self] _ in
            guard let self, self.kind == .note else { return }
            self.move(.idle, why: "camera-ended")
        }.store(in: &bag)
        // ONE subscription for the life of the recording, held here and nowhere on a screen: a
        // finished file is consumed by name exactly once, whatever the screens do around it.
        note.$finished.compactMap { $0 }.sink { [weak self] f in
            guard let self else { return }
            self.note.reset()
            if self.noteConsumed == f {
                MontanaTrace.mark("send_dup", "note \(f.prefix(24)) already sent — the tape is consumed once")
                return
            }
            self.noteConsumed = f
            self.noteSent(f)
        }.store(in: &bag)
    }

    var isRecording: Bool { phase != .idle }
    var isLocked: Bool { if case .locked = phase { return true } else { return false } }
    var kind: Kind? {
        switch phase {
        case .idle: return nil
        case .recording(let k), .locked(let k): return k
        }
    }
    var isNote: Bool { kind == .note }
    var paused: Bool { isNote ? note.paused : voice.paused }

    /// The finger landed: the tape of this kind is readied while the hold's threshold runs (the note's
    /// camera already wakes on its own queue; the voice's session and recorder are born here).
    func ready(_ k: Kind) {
        guard phase == .idle, !MontanaCall.isBusy else { return }   // under a call nothing is readied: the call holds the sound
        if k == .voice { voice.prewarm() }
    }
    /// The hold ended as a tap: nothing recorded, the readied tape goes.
    func standDown() { if phase == .idle { voice.standDown() } }

    @discardableResult
    func begin(_ k: Kind, why: String) -> Int {
        guard phase == .idle else { return tapeId }   // one tape at a time: a second begin over a rolling one is nothing
        // A CALL HOLDS THE SOUND (24.09): a tape under a call would take the phone's sound -- and a note the camera --
        // from the conversation. The person is told so, and nothing starts.
        if MontanaAudioSession.refusedUnderCall(k == .voice ? "voice tape" : "video note") { return tapeId }
        tapeId += 1
        move(.recording(k), why: why)
        if k == .voice { voice.start() }
        else if !note.start() { move(.idle, why: "camera-busy") }
        return tapeId
    }

    /// The finger rose to the lock, the system took the touch, the phone left the ear, the app
    /// folded: the tape rolls on without a finger. A lock named for an older tape is refused.
    func lock(tape: Int? = nil, why: String) {
        if let tape, tape != tapeId { MontanaTrace.mark("rec_state", "refused lock tape=\(tape) now=\(tapeId) why=\(why)"); return }
        guard case .recording(let k) = phase else { return }
        move(.locked(k), why: why)
    }

    func send(why: String) {
        guard let k = kind else { return }
        move(.idle, why: why)
        if k == .voice { voiceSent() } else { note.finish() }
    }

    func cancel(why: String) {
        guard let k = kind else { return }
        move(.idle, why: why)
        if k == .voice { voice.cancel() } else { note.cancel() }
    }

    func pauseToggle() {
        guard isRecording else { return }
        if isNote { note.togglePause() }
        else if voice.paused { voice.resume() } else { voice.pause() }
    }

    private func move(_ to: Phase, why: String) {
        MontanaTrace.mark("rec_state", "\(name(phase))→\(name(to)) why=\(why) tape=\(tapeId)")
        phase = to
    }
    private func name(_ p: Phase) -> String {
        switch p {
        case .idle: return "idle"
        case .recording(let k): return "recording-\(k.rawValue)"
        case .locked(let k): return "locked-\(k.rawValue)"
        }
    }
}
