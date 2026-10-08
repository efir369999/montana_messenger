//
//  MontanaMedia.swift
//  Montana — a Montana messenger
//
//  Cut out of ContentView.swift whole, declaration by declaration (the author's word 10.09):
//  nothing here was renamed or rewritten; the file holds one screen and what only it reads.
//

import SwiftUI
import CryptoKit
import MontanaBindings
import PhotosUI
import ImageIO
import UserNotifications
import UIKit
import Network
import AVKit
import MediaPlayer
import AVFoundation
import MediaToolbox
import LocalAuthentication
import UniformTypeIdentifiers
import CoreImage
import QuickLook
import Photos
import ContactsUI
import Contacts



// ════════════════════════════════════════════════════════════
// VOICE RECORDING — records a voice message into an .m4a file via the microphone.
// ════════════════════════════════════════════════════════════
/// THE SOUND OF A SPOKEN WORD, SET ONCE ([C-1], the author's word 18.09): the voice tape and the
/// video note's sound track are the same speech through the same door. THE REFERENCE'S QUALITY (read
/// 22.09: its tape is 48 kHz mono): 48 kHz mono, AAC at 64 kbit/s — eight kilobytes a second, the
/// voice whole and clean (the author's word 22.09). The files stay what they were (.m4a, .mov): every
/// older build plays them as before.
enum MontanaVoiceSound {
    static let settings: [String: Any] = [
        AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
        AVSampleRateKey: 48_000,
        AVNumberOfChannelsKey: 1,
        AVEncoderBitRateKey: 64_000,
    ]
    /// The tape's recorder takes the quality word too; the note's writer takes the settings alone.
    static var recorderSettings: [String: Any] {
        var s = settings; s[AVEncoderAudioQualityKey] = AVAudioQuality.max.rawValue; return s
    }
}

final class VoiceRecorder: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var paused = false               // the tape stands; the file keeps what it has
    @Published var elapsed: Double = 0          // the tape's own length (AVAudioRecorder.currentTime), asked every tenth
    @Published var levels: [Float] = []         // the live wave: the meter's power, newest last
    static let levelCount = 240   // six seconds of 25 ms slots: the wave's room holds up to ~120 lines
    private var recorder: AVAudioRecorder?
    private var meter: CADisplayLink?
    /// A line of the wave is one slot of time — the reference's 1200 samples at 48 kHz, 25 ms; the
    /// reading is taken every frame and the slot keeps its loudest.
    static let slot: TimeInterval = 0.025
    private var slotStart: TimeInterval = 0
    /// THE WAVE IS THE SOUND ITSELF: a slot keeps the linear amplitude 10^(dB/20) of its loudest reading —
    /// no curve, no floor. THE REFERENCE'S FULL LEVEL (read 22.09, ManagedAudioRecorder: micLevel =
    /// peak / 4000 of an Int16): a sample of 4000 — −18 dBFS — is the whole height; louder than that a
    /// tape's own loudest word is (the reference's waveform is scaled to its peak). One rule for the
    /// lines and the swell.
    static let referenceFull: Float = 4000 / 32767
    static func shown(_ amp: Float, peak: Float) -> Float { min(1, amp / max(peak, referenceFull)) }
    private var fileName: String?
    /// The finger is still down. A permission answer arrives on its own tick; a release in that
    /// gap used to stop a tape not yet started, and the tape then started without a finger and
    /// could not be ended. Now the answer starts nothing once the hold is over.
    private var armed = false
    /// THE TAPE IS READIED UNDER THE FINGER (21.09, measured on T1: the session's activation and the
    /// recorder's birth stood 300–1000 ms on the MAIN thread after the hold began, and the swell came
    /// that late). They are born on their own queue the moment the finger lands; the hold's threshold
    /// (190 ms) runs meanwhile, and the start is one `record()` on a recorder already prepared.
    private static let q = DispatchQueue(label: "montana.voice.tape", qos: .userInteractive)
    private var prepared: (AVAudioRecorder, String, String)?
    private var preparing = false
    private var request = 0
    private var audioLease: String?
    var onFailure: () -> Void = {}
    private static func born(_ name: String, lease: String) -> AVAudioRecorder? {
        // THE PLAIN MICROPHONE (the author's word 17.09: the tapes came out quiet) — the one
        // recording door of the tree (MontanaAudioSession.record), the video note's too.
        guard MontanaAudioSession.record(lease) else { return nil }
        let r = try? AVAudioRecorder(url: voiceRecordURL(name), settings: MontanaVoiceSound.recorderSettings)
        r?.isMeteringEnabled = true
        _ = r?.prepareToRecord()
        return r
    }
    func prewarm() {
        guard !isRecording, prepared == nil, !preparing, AVAudioApplication.shared.recordPermission == .granted else { return }
        request += 1
        prepare(request: request, start: false)
    }

    func standDown() {
        guard !armed, !isRecording else { return }
        request += 1
        preparing = false
        if let (r, name, lease) = prepared {
            prepared = nil
            Self.discard(r, name: name, lease: lease)
        }
    }

    func start() {
        guard !isRecording else { return }
        MontanaPlayerBar.standDown()
        armed = true
        request += 1
        let ticket = request
        if let (r, name, lease) = prepared {
            prepared = nil
            begin(r, name, lease: lease)
            return
        }
        if AVAudioApplication.shared.recordPermission == .granted {
            prepare(request: ticket, start: true)
            return
        }
        AVAudioApplication.requestRecordPermission { [weak self] granted in
            DispatchQueue.main.async {
                guard let self, self.armed, self.request == ticket else { return }
                guard granted else { self.armed = false; self.onFailure(); return }
                self.prepare(request: ticket, start: true)
            }
        }
    }

    private func prepare(request ticket: Int, start: Bool) {
        preparing = true
        let name = "voice_\(UUID().uuidString).m4a"
        let lease = "voice:" + name
        Self.q.async { [weak self] in
            let r = Self.born(name, lease: lease)
            DispatchQueue.main.async {
                guard let self, self.request == ticket else {
                    Self.discard(r, name: name, lease: lease)
                    return
                }
                self.preparing = false
                guard let r else {
                    Self.discard(nil, name: name, lease: lease)
                    if start { self.armed = false; self.onFailure() }
                    return
                }
                if start, self.armed, !self.isRecording { self.begin(r, name, lease: lease) }
                else if !start, !self.armed, !self.isRecording { self.prepared = (r, name, lease) }
                else { Self.discard(r, name: name, lease: lease) }
            }
        }
    }

    private static func discard(_ recorder: AVAudioRecorder?, name: String, lease: String) {
        recorder?.stop()
        MontanaAudioSession.release(lease)
        try? FileManager.default.removeItem(at: voiceRecordURL(name))
    }

    private func begin(_ r: AVAudioRecorder, _ name: String, lease: String) {
        guard r.record() else {
            armed = false
            Self.discard(r, name: name, lease: lease)
            onFailure()
            return
        }
        recorder = r
        audioLease = lease
        fileName = name
        elapsed = 0; levels = []; paused = false
        isRecording = true
        MontanaScreenAwake.hold("voice")
        MontanaTrace.mark("voice_rec", "start")
        // NATIVE-CHECKED: the clock and the wave are the recorder's own readings (currentTime,
        // peakPower), asked at the screen's own pace (CADisplayLink, the reference's mic button's
        // clock too) so no swing of the voice falls between two readings; a bar of the wave keeps
        // the loudest reading of its slot (the author's word 21.09: the wave reacts to the sound as
        // the platform's recorder does).
        slotStart = 0
        let link = CADisplayLink(target: self, selector: #selector(meterTick))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 40, preferred: 40)
        link.add(to: .main, forMode: .common)
        meter = link
    }
    @objc private func meterTick(_ link: CADisplayLink) {
        guard let r = recorder, isRecording else { meter?.invalidate(); meter = nil; return }
        elapsed = r.currentTime
        guard !paused else { return }
        r.updateMeters()
        let db = r.peakPower(forChannel: 0)                                  // -160…0 dB, the loudest since the last reading
        let level = min(1, powf(10, db / 20))                                 // linear amplitude, as it is
        let now = link.timestamp
        if slotStart == 0 || now - slotStart >= Self.slot || levels.isEmpty {
            slotStart = now
            levels.append(level)
            if levels.count > VoiceRecorder.levelCount { levels.removeFirst(levels.count - VoiceRecorder.levelCount) }
        } else if level > levels[levels.count - 1] {
            levels[levels.count - 1] = level                                   // the slot keeps its loudest
        }
    }

    /// The tape stands and keeps what it has; `resume` continues the same file.
    func pause() {
        guard isRecording, !paused else { return }
        recorder?.pause(); paused = true
    }
    func resume() {
        guard isRecording, paused else { return }
        if recorder?.record() == true { paused = false }
    }

    /// -> TAPE THAT IS DONE BUT NOT YET SENT (the author's word 23.09: listen to it before sending).
    /// The sound is AAC inside an m4a, and such a file becomes playable only when its container is
    /// closed — so a preview has to END the tape. The closed file and its length wait here, and
    /// `stop()` hands them on as though the tape had just been stopped: the send road does not learn
    /// a new way, and the bin still deletes one file.
    @Published private(set) var reviewed: (name: String, dur: Double)?
    var hasReview: Bool { reviewed != nil }
    /// Close the tape for listening. The name is the file's; nil when nothing was recorded.
    @discardableResult
    func finishForReview() -> String? {
        if let r = reviewed { return r.name }
        guard let (n, d) = close() else { return nil }
        reviewed = (n, d)
        MontanaTrace.mark("voice_rec", "closed for the ear dur=" + String(Int(d * 10)))
        return n
    }

    // finish and return (file name, duration); nil if too short
    func stop() -> (String, Double)? {
        if let r = reviewed { reviewed = nil; return (r.name, r.dur) }   // the tape the person has already heard
        return close()
    }
    private func close() -> (String, Double)? {
        armed = false
        request += 1
        standDown()
        meter?.invalidate(); meter = nil
        let dur = recorder?.currentTime ?? 0    // the tape's own length, read before stop() zeroes it
        recorder?.stop(); recorder = nil
        isRecording = false; paused = false
        MontanaScreenAwake.release("voice")
        if let lease = audioLease { audioLease = nil; MontanaAudioSession.release(lease) }
        MontanaTrace.mark("voice_rec", "stop dur=\(Int(dur * 10)) peak=\(Int((levels.max() ?? 0) * 1000)) mean=\(levels.isEmpty ? 0 : Int(levels.reduce(0, +) / Float(levels.count) * 1000))")   // thousandths of full scale: the microphone's level under the platform's processing, measured
        let name = fileName
        fileName = nil
        guard let n = name, dur >= 0.6 else {
            if let n = name { try? FileManager.default.removeItem(at: voiceFileURL(n)) }
            return nil
        }
        return (n, dur)
    }

    // cancel and delete the file
    func cancel() {
        armed = false
        request += 1
        standDown()
        meter?.invalidate(); meter = nil
        recorder?.stop(); recorder = nil
        isRecording = false; paused = false
        MontanaScreenAwake.release("voice")
        if let lease = audioLease { audioLease = nil; MontanaAudioSession.release(lease) }
        MontanaTrace.mark("voice_rec", "cancel")
        if let n = fileName { try? FileManager.default.removeItem(at: voiceFileURL(n)) }
        if let r = reviewed { try? FileManager.default.removeItem(at: voiceFileURL(r.name)); reviewed = nil }   // the heard tape goes with the bin too
        fileName = nil
    }
}

// ════════════════════════════════════════════════════════════
// VOICE PLAYER — one per chat; plays voice messages one after another.
// ════════════════════════════════════════════════════════════
final class VoicePlayer: NSObject, ObservableObject {
    /// One player per app: music outlives the chat screen, plays with
    /// the app folded (background audio mode) and is controlled from the lock screen.
    static let shared = VoicePlayer()
    /// THE PLAYER'S FACE (28.09): what a letter's bubble draws of the player -- which file plays, whether it rests, its length and
    /// the voice's speed -- published when one of them moves, never at the clock's tick. Every bubble in view watched the whole
    /// player and was drawn again four times a second under any sound; a bubble watches this face now, and only the playing
    /// bubble's wave watches the clock (MTAudioLive). The player alone writes it, in the moment its own words change.
    /// The queue's state belongs to the face too, so the big player's head redraws on a change of track, not on the clock.
    final class Face: ObservableObject {
        @Published fileprivate(set) var playingFile: String?
        @Published fileprivate(set) var paused = false
        @Published fileprivate(set) var duration: Double = 0
        @Published fileprivate(set) var voiceRate: Float = 1
        @Published fileprivate(set) var queueIndex = -1
        @Published fileprivate(set) var repeatOn = false
        @Published fileprivate(set) var repeatAll = false
        @Published fileprivate(set) var shuffleOn = false
        @Published fileprivate(set) var isVoice = false
    }
    let face = Face()
    @Published var playingFile: String? = nil { didSet { if face.playingFile != playingFile { face.playingFile = playingFile } } }   // which file is currently playing
    @Published var paused = false { didSet { if face.paused != paused { face.paused = paused } } }
    @Published var progress: Double = 0         // 0..1 for the bar in the bubble
    @Published var duration: Double = 0 { didSet { if face.duration != duration { face.duration = duration } } }
    @Published var elapsed: Double = 0          // seconds, for the player page
    // The chat's music as a queue: the page walks it, the bubble only starts it.
    var queue: [MusicTrack] = []
    @Published var queueIndex: Int = -1 { didSet { if face.queueIndex != queueIndex { face.queueIndex = queueIndex } } }
    @Published var repeatOn = false { didSet { if face.repeatOn != repeatOn { face.repeatOn = repeatOn } } }   // the track again
    @Published var repeatAll = false { didSet { if face.repeatAll != repeatAll { face.repeatAll = repeatAll } } }   // the playlist again
    /// THE REPEAT'S ROUND (the author's word 01.10 00:42: «the repeat repeats the chosen track in a circle, a second tap repeats the
    /// playlist, a third takes it all off»): off, the track, the playlist, off.
    func turnRepeat() {
        if repeatOn { repeatOn = false; repeatAll = true }
        else if repeatAll { repeatAll = false }
        else { repeatOn = true }
        MontanaTrace.mark("music", "repeat \(repeatOn ? "track" : (repeatAll ? "playlist" : "off"))")
    }
    @Published var shuffleOn = false { didSet { if face.shuffleOn != shuffleOn { face.shuffleOn = shuffleOn } } }
    @Published var rate: Float = 1 { didSet { player?.rate = rate } }
    /// Voice and music are two things (the author's word 10.09): a voice message never enters
    /// the music queue, the folded bar and the page show music only, and voice has its own
    /// speed (1 / 1.5 / 2) while music always plays at one.
    @Published var isVoice = false { didSet { if face.isVoice != isVoice { face.isVoice = isVoice } } }
    @Published var voiceRate: Float = UserDefaults.standard.object(forKey: "voiceRate") == nil ? 1 : UserDefaults.standard.float(forKey: "voiceRate") {
        didSet {
            UserDefaults.standard.set(voiceRate, forKey: "voiceRate")
            if isVoice { player?.rate = voiceRate }
            if face.voiceRate != voiceRate { face.voiceRate = voiceRate }
        }
    }
    /// A copy laid under the player (23.09): the voice's speed is read from the store again.
    func rereadRate() {
        voiceRate = UserDefaults.standard.object(forKey: "voiceRate") == nil ? 1 : UserDefaults.standard.float(forKey: "voiceRate")
    }
    var currentTrack: MusicTrack? { queueIndex >= 0 && queueIndex < queue.count ? queue[queueIndex] : nil }
    private var playRequest = 0
    private var player: MTSound? { didSet { if metering { player?.metering = true } } }   // the sound under the one player: a file's, or a stream's (25.09)
    /// THE BIG COVER LISTENS (30.09): while its waves stand the sound in hand keeps its meter on (MTSound.level); the cover alone
    /// sets it and lets it go (MTCoverWaves).
    var metering = false { didSet { player?.metering = metering } }
    /// The level of the music that plays, once a frame for the cover's waves: silence while it rests or a voice holds the player.
    func level() -> Float { metering && !paused && !isVoice ? (player?.level() ?? 0) : 0 }
    private var tick: Timer?
    private var nowTitle = ""
    @Published var nowSender = ""   // who speaks in the voice that plays — the bar's heading
    @Published var nowChat = ""     // the chat the voice plays in — the bar's way back to its bubble
    /// The chat's voices in feed order, set when one starts: auto-next walks it forward.
    var voiceQueue: [(file: String, sender: String, mine: Bool)] = []
    /// THE TRACK UNDER A VOICE OR A NOTE KEEPS ITS PLACE (the author's word 26.09: «the mini player must remember the place where it
    /// stopped playing and not be reset by recording or listening to a voice or a video message»; the reference read the same day --
    /// its media manager pauses the music's player when a voice starts and never stops it, and once the voice's player is gone the
    /// music's paused state is what its bar shows again). One sound plays at a time still: the track steps aside, paused, with its
    /// sound, its name and its place, while the voice or the note plays; when they end -- or are closed -- it comes back to the bar
    /// paused where it stood, and its play goes on from there. A new track chosen meanwhile lets it go.
    private struct Parked { let sound: MTSound; let file: String; let title: String }
    private var parked: Parked?

    /// Start (or resume) a voice with the chat's voices behind it for auto-next.
    func playVoice(_ file: String, sender: String, chat: String = "", queue: [(file: String, sender: String, mine: Bool)]) {
        voiceQueue = queue; nowChat = chat
        MontanaTrace.mark("voice_play", "file=\(String(file.prefix(14))) queue=\(queue.count) at=\(queue.firstIndex { $0.file == file } ?? -1)")
        toggle(file, title: sender, voice: true)
    }

    func toggle(_ file: String, title: String = "", voice: Bool = false, stream: MTStreamSource? = nil, whole: (() -> Void)? = nil) {
        if playingFile == file {
            if paused { resume() } else { pause() }
            return
        }
        // THE CALL HOLDS THE SOUND (24.09, T1 12:31:40): under a call the player never touches the phone's sound -- the
        // person is told so and nothing starts (MontanaAudioSession, the one door).
        guard !MontanaAudioSession.refusedUnderCall(voice ? "voice message" : "music") else { return }
        // THE TRACK THAT STEPPED ASIDE IS THE ONE ASKED FOR (26.09): the voice over it ends and the track goes on from its place.
        if !voice, let pk = parked, pk.file == file {
            release()
            MontanaVideoDock.shared.close()   // the one bar, one thing playing
            unpark()
            resume()
            return
        }
        // A voice takes the player: a track in it steps aside with its place -- and the bar's facts stay the track's until the
        // voice starts (park(handing:)). A new track lets the one aside go.
        if voice { park(handing: true) } else { dropParked() }
        // The sound in hand before this one keeps its place when its listen is a long one; a voice's next voice follows it
        // directly, as ever.
        if let p = player, let f = playingFile { MTPlayPlaces.keep(f, at: p.currentTime, of: p.duration, voice: isVoice) }
        isVoice = voice
        if voice, parked == nil { queueIndex = -1 }   // the music queue steps aside: no bar, no page for a voice; a track aside keeps its place until the voice starts
        MontanaVideoDock.shared.close()   // the one bar, one thing playing
        playRequest += 1
        let ticket = playRequest
        let external = voice && MontanaAudioRoute.read("voice").isExternal
        disarmProximity()
        // Voice plays FROM MEMORY: an open file on disk has no place here. A lent folder's track is read where it lies
        // (MTMusicFolders): the folder is the person's, and a whole album is not taken into memory.
        if let lent = MTMusicFolders.url(file) {
            player = MTFileSound(url: lent)
        } else {
            player = MontanaMediaVault.data(file).flatMap { MTFileSound(data: $0) } ?? MTFileSound(url: voiceFileURL(file))
        }
        // A TRACK NOT YET WHOLE (the author's word 25.09: «a tap on a track starts it at once, with a buffer»): the streaming
        // player on the track's loader — from its first pieces, a few seconds buffered ahead, never the whole file first.
        if player == nil, let stream {
            player = MTStreamSound(asset: MTStreams.asset(stream, whole: whole))
            MontanaTrace.mark("music_stream", "file=\(String(file.prefix(20))) pieces=\(stream.chunks.count)")
        }
        player?.onEnd = { [weak self] in self?.finished() }
        player?.rate = voice ? voiceRate : 1
        // A LONG LISTEN GOES ON WHERE IT STOPPED (the reference's stored playback state, 26.09): a track of ten minutes and more, a
        // voice of five, starts at its kept moment (MTPlayPlaces); a stream starts where its pieces begin.
        if let p = player as? MTFileSound, let at = MTPlayPlaces.at(file, of: p.duration, voice: voice) {
            p.currentTime = at
            MontanaTrace.mark("play_place", "from=\(Int(at))s voice=\(voice ? 1 : 0)")
        }
        MontanaAudioSession.wake(voice: voice, external: external) { [weak self] ready in
            guard let self, self.playRequest == ticket else { return }
            guard ready, !MontanaCall.isBusy, self.player?.play() == true else {
                // A file that would not play is said, not swallowed (the critic 24.09).
                MontanaTrace.mark("play_refused", "voice=\(voice ? 1 : 0) lent=\(MTMusicFolders.isLent(file) ? 1 : 0) opened=\(self.player == nil ? 0 : 1)")
                self.player?.stop(); self.player = nil   // the sound that would not play is let go before the ledger keeps a place under the track's file
                self.release()
                self.unpark()   // the track aside comes back to the bar, paused where it stood
                return
            }
            if voice, !external { self.armProximity(); self.routeVoice(near: UIDevice.current.proximityState) }
            if voice { self.queueIndex = -1; self.progress = 0; self.elapsed = 0 }   // the track's facts give way to the voice's in this one turn
            self.playingFile = file
            self.paused = false
            if voice { ChatStore.live?.notePlayed(file: file) }   // their voice played here: its sender learns it (25.09)
            self.duration = self.player?.duration ?? 0
            self.nowTitle = title.isEmpty ? String(localized: "Voice message", bundle: MTLanguage.bundle) : title
            if voice { self.nowSender = title }
            if !voice { self.armRemote(); self.pushNowPlaying() }   // the lock screen is the music's, not a voice's
            self.startTick()
        }
    }

    func pause() {
        playRequest += 1
        player?.pause(); paused = true
        MontanaAudioSession.release("play")
        disarmProximity()
        pushNowPlaying()
        if let p = player, let f = playingFile { MTPlayPlaces.keep(f, at: p.currentTime, of: p.duration, voice: isVoice) }
    }
    /// A CALL TAKES THE SOUND (24.09): a track or a voice playing when a call is born stands down -- left playing it
    /// would sound in the call's voice mode, into the conversation, and under a call the player never takes the sound back.
    func yieldToCall() {
        guard playingFile != nil, !paused else { return }
        pause()
        MontanaTrace.mark("music_yield", "voice=\(isVoice ? 1 : 0) -- the call took the sound")
    }

    // ── the ear: the proximity sensor routes a playing voice to the receiver ──
    private var proximityArmed = false
    private func armProximity() {
        guard !proximityArmed else { return }
        proximityArmed = true
        MTProximity.hold("voice", true)   // the sensor's one owner (24.09)
        NotificationCenter.default.addObserver(self, selector: #selector(proximityChanged),
                                               name: UIDevice.proximityStateDidChangeNotification, object: nil)
    }
    /// The voice lets go of the sensor. When the last voice ended AT THE EAR the chat takes the sensor over by its own
    /// hold to record the reply (the author's word 14.09); a phone still at the ear keeps the sensor on meanwhile, since
    /// the owner never turns it off while the sensor says «near».
    private func disarmProximity() {
        guard proximityArmed else { return }
        proximityArmed = false
        NotificationCenter.default.removeObserver(self, name: UIDevice.proximityStateDidChangeNotification, object: nil)
        MTProximity.hold("voice", false)
    }
    @objc private func proximityChanged() {
        routeVoice(near: UIDevice.current.proximityState)
    }
    private func routeVoice(near: Bool) {
        if MontanaAudioRoute.read("voice-route").isExternal { return }   // the headset holds the sound — no override over it
        MontanaAudioSession.routeVoice(near: near)
        MontanaTrace.mark("voice_route", near ? "ear" : "speaker")
    }

    func resume() {
        guard !MontanaAudioSession.refusedUnderCall(isVoice ? "voice message" : "music") else { return }
        // THROUGH THE KIND'S OWN DOOR (26.09): a tape or a voice between the pause and this resume left the sound in their own mode.
        let external = isVoice && MontanaAudioRoute.read("voice-resume").isExternal
        playRequest += 1
        let ticket = playRequest
        MontanaAudioSession.wake(voice: isVoice, external: external) { [weak self] ready in
            guard let self, self.playRequest == ticket else { return }
            guard ready, !MontanaCall.isBusy, self.player?.play() == true else {
                MontanaAudioSession.release("play"); return
            }
            self.paused = false
            if self.isVoice, !external { self.armProximity(); self.routeVoice(near: UIDevice.current.proximityState) }
            self.pushNowPlaying()
            self.startTick()
        }
    }

    func seek(to fraction: Double) {
        guard let p = player, p.duration > 0 else { return }
        // THE CLOCK DIES ON A SEEK MID-PLAY (the author's word 16.09: the slider died, the car's
        // panel hung, the music went on). The system player keeps playing after its position is
        // set on the fly, but its own currentTime stops advancing — and every reader of that
        // clock (the slider, the bar, the lock screen, the car) freezes on the sought second.
        // The position is set AT REST: pause, position, play — the platform's own road.
        let began = ProcessInfo.processInfo.systemUptime
        let wasPlaying = p.isPlaying
        if wasPlaying { p.pause() }
        p.currentTime = max(0, min(p.duration - 0.2, p.duration * fraction))
        if wasPlaying { p.play() }
        // Nothing optimistic is published (the author's word 18.09: the thumb jumped after a seek):
        // the tick reads the player's own clock, and the scrubber holds the asked place until it does.
        pushNowPlaying()
        let ms = Int((ProcessInfo.processInfo.systemUptime - began) * 1000)
        MontanaTrace.mark("seek", "\(isVoice ? "voice" : "music") to=\(Int(p.currentTime))s playing=\(wasPlaying ? 1 : 0) ms=\(ms)")
    }

    func stop() {
        release()
        unpark()   // a voice or a note over a track gives the bar back to the track, paused where it stood (26.09)
    }
    /// The sound in hand stops and lets go; its place is kept when its listen is a long one (MTPlayPlaces).
    private func release() {
        playRequest += 1
        disarmProximity()
        if let p = player, let f = playingFile { MTPlayPlaces.keep(f, at: p.currentTime, of: p.duration, voice: isVoice) }
        player?.stop(); player = nil; playingFile = nil; paused = false
        progress = 0; duration = 0
        tick?.invalidate(); tick = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        MontanaAudioSession.release("play")   // the sound in hand is let go: the ledger closes what it opened (28.09)
    }

    // ── THE TRACK UNDER A VOICE OR A NOTE (26.09) ──
    /// The track in hand steps aside for a voice or a note: paused where it stands, kept with its sound, its name and its place.
    /// HANDING OVER TO A VOICE, THE BAR NEVER FALLS (28.09, T1 17:45:00Z: the bar fell at the tap and rose again 75 ms later as
    /// the voice's, the feed's inset 180, 128, 180 with it -- the screen flickered at every tap on a voice). The voice's start is
    /// a turn away (the sound's session wakes first), so the bar's facts -- the file, the queue's place, the clock, the rest --
    /// stay the track's until the voice's start writes them over in one turn (toggle), and a refused start gives the track back
    /// (unpark). A note takes the stage at once (stepAside), so for it they are cleared here as before.
    private func park(handing: Bool = false) {
        guard !isVoice, let s = player, let f = playingFile, currentTrack != nil else { return }
        playRequest += 1
        s.pause()
        MontanaAudioSession.release("play")
        MTPlayPlaces.keep(f, at: s.currentTime, of: s.duration, voice: false)
        parked = Parked(sound: s, file: f, title: nowTitle)
        tick?.invalidate(); tick = nil
        player = nil
        if !handing {
            playingFile = nil; paused = false; queueIndex = -1
            progress = 0; duration = 0; elapsed = 0
        }
        MontanaTrace.mark("music_park", "aside at=\(Int(s.currentTime))s handing=\(handing ? 1 : 0)")
    }
    /// The voice or the note is over: the track that stepped aside comes back to the bar, paused where it stood. While anything
    /// else is in hand, it waits.
    private func unpark() {
        guard let pk = parked, playingFile == nil else { return }
        parked = nil
        guard let i = queue.firstIndex(where: { $0.file == pk.file }) else {
            pk.sound.stop()
            MontanaTrace.mark("music_park", "let go -- the queue no longer holds it")
            return
        }
        player = pk.sound
        isVoice = false
        queueIndex = i
        playingFile = pk.file
        paused = true
        nowTitle = pk.title
        duration = pk.sound.duration
        elapsed = pk.sound.currentTime
        progress = duration > 0 ? elapsed / duration : 0
        armRemote(); pushNowPlaying()
        MontanaTrace.mark("music_park", "back at=\(Int(elapsed))s paused")
    }
    /// Another track was chosen: the one aside lets go, its place kept when its listen is a long one.
    private func dropParked() {
        guard let pk = parked else { return }
        parked = nil
        MTPlayPlaces.keep(pk.file, at: pk.sound.currentTime, of: pk.sound.duration, voice: false)
        pk.sound.stop()
        MontanaTrace.mark("music_park", "let go -- another track")
    }
    /// A NOTE OPENS OVER WHAT PLAYS (26.09): a voice stands down; a track steps aside with its place, as it does under a voice.
    func stepAside() {
        if isVoice { release() } else { park() }
    }
    /// The note's player let go: the track aside comes back one turn later -- a voice or a track started in the turn that closed
    /// the note keeps the player.
    func noteClosed() {
        DispatchQueue.main.async { [weak self] in self?.unpark() }
    }
    /// A TAPE TAKES THE MICROPHONE, NOT THE PLACE (the author's word 26.09: «not reset by recording»; the reference pauses what
    /// plays when a recording begins, and stops nothing): what plays pauses where it stands and stays on the bar; its play goes on
    /// from there after the tape.
    func holdForTape() {
        playRequest += 1
        MontanaAudioSession.release("play")
        guard playingFile != nil, !paused else { return }
        pause()
        MontanaTrace.mark("music_hold", "tape voice=\(isVoice ? 1 : 0) at=\(Int(elapsed))s")
    }

    /// The sound ran to its end — the file player's word and the stream player's alike.
    private func finished() {
        if currentTrack != nil {
            if repeatOn { play(index: queueIndex); return }
            if let nx = nextIndex() { play(index: nx); return }
            if repeatAll, !queue.isEmpty { play(index: 0); return }   // the playlist from its first track again
        }
        // A voice is followed by the chat's next voice, always (the author's word 14.09) —
        // A to B directly: the player never passes through «nothing playing» between them,
        // so the bar stands and the feed's reserve does not flicker.
        if isVoice, let f = playingFile,
           let i = voiceQueue.firstIndex(where: { $0.file == f }), i + 1 < voiceQueue.count {
            let n = voiceQueue[i + 1]
            MontanaTrace.mark("voice_next", "i=\(i + 1) n=\(voiceQueue.count)")
            toggle(n.file, title: n.sender, voice: true)
            return
        }
        if isVoice {
            // The reply at the ear follows the PEER's voice only (the author's word 14.09): one's
            // own voice, listened back, asks for no answer.
            let theirs = voiceQueue.first { $0.file == playingFile }.map { !$0.mine } ?? false
            let atEar = proximityArmed && UIDevice.current.proximityState && theirs
            MontanaTrace.mark("voice_end", "queue=\(voiceQueue.count) ear=\(atEar ? 1 : 0) theirs=\(theirs ? 1 : 0)")
            stop()
            if atEar { NotificationCenter.default.post(name: .montanaVoiceEndedAtEar, object: nil) }
            return
        }
        stop()
    }

    private func nextIndex() -> Int? {
        guard !queue.isEmpty else { return nil }
        if shuffleOn { return queue.indices.filter { $0 != queueIndex }.randomElement() }
        let nx = queueIndex + 1
        return nx < queue.count ? nx : nil
    }

    /// A lent folder's track its keeper is bringing for this play (MTMusicFolders.bring): it plays when it arrives,
    /// unless another play came first.
    private var awaited: String?
    func play(index: Int) {
        guard index >= 0, index < queue.count else { return }
        let t = queue[index]
        // A TRACK WHOSE BYTES ITS KEEPER HOLDS is brought first: opening it here would fetch it whole on the main thread.
        if MTMusicFolders.needsFetch(t.file) {
            // The track in hand is the one being brought: what played stops, as at any change of track, and the queue
            // stands on it — the bar and the page name what comes, never what went. A track aside for a voice lets go too.
            dropParked(); release()
            queueIndex = index
            awaited = t.file
            MTMusicFolders.bring(t.file) { [weak self] in
                guard let self, self.awaited == t.file, let i = self.queue.firstIndex(where: { $0.file == t.file }) else { return }
                self.awaited = nil
                self.start(index: i)
            }
            return
        }
        awaited = nil
        start(index: index)
    }
    private func start(index: Int) {
        queueIndex = index
        let t = queue[index]
        // THE TRACK AGAIN PLAYS AGAIN (T2 05.10.2026 15:36:27Z, the author: «it ended and did not repeat, though the repeat-1 stood
        // lit»): a track that ran to its end is stopped by the system, not paused by the person -- the seek set it to its start and
        // the resume waited for a pause that never came (diary: seek music to=0s playing=0). A stopped track plays again.
        if playingFile == t.file {
            seek(to: 0)
            if paused || player?.isPlaying != true { resume() }
            MontanaTrace.mark("music_again", "i=\(index + 1) repeat=\(repeatOn ? "track" : (repeatAll ? "playlist" : "off"))")
            return
        }
        toggle(t.file, title: (t.title as NSString).deletingPathExtension, stream: t.stream, whole: t.whole)
        MontanaTrace.mark("music_play", "i=\(index + 1) n=\(queue.count) shuffle=\(shuffleOn ? 1 : 0) repeat=\(repeatOn ? 1 : 0)")
    }

    /// A TRACK TAKEN OUT OF THE QUEUE (the author's word 29.09 ~23:22: «the tracks' bubbles in the playlist with the swipe of
    /// deletion, short and long»): the queue, the playlist's one owner, lets it go -- its file and its letter stay where they lie.
    /// The track that plays, taken out, gives the player to the one after it by the queue's own turn (next); the last track
    /// taken out stops the music.
    func dropFromQueue(_ file: String) {
        guard let i = queue.firstIndex(where: { $0.file == file }) else { return }
        let was = i == queueIndex
        objectWillChange.send()
        queue.remove(at: i)
        MontanaTrace.mark("music_queue", "out i=\(i + 1) n=\(queue.count) playing=\(was ? 1 : 0)")
        if i < queueIndex { queueIndex -= 1; return }
        guard was else { return }
        if queue.isEmpty { queueIndex = -1; stop(); return }
        queueIndex = i - 1   // the turn goes on from the place the track stood
        next()
    }

    /// The forward button turns the page even on the last track — the first follows (the author's
    /// word 16.09). Repeat governs what happens when a track ENDS by itself, not the button.
    func next() {
        if let nx = nextIndex() { play(index: nx) } else if !queue.isEmpty { play(index: 0) }
    }

    func prev() {
        if (player?.currentTime ?? elapsed) > 3 { seek(to: 0); return }   // the sound's own clock: the published one rests in the background
        let pv = queueIndex - 1
        if pv >= 0 { play(index: pv) } else { seek(to: 0) }
    }

    private func startTick() {
        tick?.invalidate()
        // NATIVE-CHECKED: the clock reads the player's own currentTime; the timer only asks it.
        // In the COMMON modes: a scheduled timer lives in the default mode and stands still while
        // the finger scrolls the feed (14.09: the bar «hung» on the previous voice mid-scroll).
        // NOTHING IS SAID TO A SCREEN NOBODY SEES, AND NOTHING THAT DID NOT MOVE (28.09): every word of this clock redraws every
        // view that watches the player -- each bubble of an open chat among them -- and it spoke four times a second in the
        // background under music, twice a tick, and on a paused track too. The lock screen reads the system's own clock
        // (MPNowPlayingInfoCenter); the first tick after the return says where the track stands.
        let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self, let p = self.player, UIApplication.shared.applicationState != .background else { return }
            let at = p.currentTime
            if self.elapsed != at { self.elapsed = at }
            let share = p.duration > 0 ? at / p.duration : self.progress
            if self.progress != share { self.progress = share }
        }
        RunLoop.main.add(t, forMode: .common)
        tick = t
    }

    // Lock screen and headphones: track title, time, pause/resume.
    private func pushNowPlaying() {
        guard let p = player else { return }
        let own = ownFace()
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: nowTitle,
            // The artist its own tags name, never where the track lies (the author's word 29.09 ~23:20); none named -- the app's name.
            MPMediaItemPropertyArtist: own.artist ?? "Montana",
            MPMediaItemPropertyPlaybackDuration: p.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: p.currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: paused ? 0.0 : 1.0]
        // THE LOCK SCREEN'S PICTURE (the author's word 29.09 ~23:10): the track's own cover, else the app's own icon (MTMusicArt).
        if let art = MTMusicArt.artwork(own.cover) { info[MPMediaItemPropertyArtwork] = art }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
    /// THE PLAYING TRACK'S OWN COVER AND ARTIST (MTTrackMeta, whose readings live on the main thread): what its reading holds; a
    /// whole file whose cover is not known is asked for its reading, and the lock screen takes what it finds the moment it lands
    /// (readingLanded). A stream is not read before it is whole: its reading would keep «no cover» for the session.
    private func ownFace() -> (cover: UIImage?, artist: String?) {
        guard let f = playingFile, !isVoice, Thread.isMainThread else { return (nil, nil) }
        let whole = player is MTFileSound
        let face = MainActor.assumeIsolated { () -> (cover: UIImage?, artist: String?) in
            let meta = MTTrackMeta.shared
            let cover = meta.cover(f)
            if cover == nil, whole { meta.load(f) }
            return (cover, meta.byline(f))
        }
        // The cover at the lock screen's measure once it is read; the row's small reading only until then.
        if let big = lockCover, big.file == f { return (big.image, face.artist) }
        if face.cover != nil, whole, lockAsked != f { readWholeCover(f) }
        return face
    }
    /// THE LOCK SCREEN'S WHOLE COVER (MTTrackMeta.wholeCover, the author's picture 30.09 00:41: the row's 174-pixel reading stood small
    /// in a wide card with bars of its colour): read once per track that plays, off the main thread, and pushed the moment it lands.
    private var lockCover: (file: String, image: UIImage)?
    private var lockAsked: String?
    private func readWholeCover(_ f: String) {
        lockAsked = f
        Task.detached(priority: .utility) { [weak self] in
            let image = await MTTrackMeta.wholeCover(f)
            await MainActor.run { [weak self] in
                guard let self, let image, self.playingFile == f else { return }
                self.lockCover = (f, image)
                MontanaTrace.mark("music_meta", "lock cover px=\(Int(image.size.width * image.scale))")
                self.pushNowPlaying()
            }
        }
    }
    /// A reading of a track's tags landed (MTTrackMeta): the track that plays says its cover and its artist on the lock screen at once.
    func readingLanded(_ file: String) {
        guard file == playingFile, !isVoice, player != nil else { return }
        pushNowPlaying()
    }

    private var remoteArmed = false
    private func armRemote() {
        guard !remoteArmed else { return }
        remoteArmed = true
        UIApplication.shared.beginReceivingRemoteControlEvents()
        let c = MPRemoteCommandCenter.shared()
        c.playCommand.addTarget { [weak self] _ in self?.resume(); return .success }
        c.pauseCommand.addTarget { [weak self] _ in self?.pause(); return .success }
        c.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            if self.paused { self.resume() } else { self.pause() }
            return .success
        }
        c.nextTrackCommand.addTarget { [weak self] _ in self?.next(); return .success }
        c.previousTrackCommand.addTarget { [weak self] _ in self?.prev(); return .success }
        c.changePlaybackPositionCommand.addTarget { [weak self] e in
            guard let self, let ev = e as? MPChangePlaybackPositionCommandEvent,
                  let p = self.player, p.duration > 0 else { return .commandFailed }
            self.seek(to: ev.positionTime / p.duration)
            return .success
        }
    }
}

/// WHERE A LONG LISTEN STOPPED (the reference's stored playback state, read 26.09 in its media manager: a track of ten minutes and
/// more, a voice of five, keeps its moment when it stops -- between five seconds in and five before its end -- and the next play of
/// the same file starts there). One owner, one key of the defaults, written when a listen stops, never by the clock, and bounded to
/// the newest two hundred.
enum MTPlayPlaces {
    private static let key = "playPlaces"
    private static let most = 200
    static func long(_ duration: Double, voice: Bool) -> Bool { !(duration < (voice ? 300 : 600)) }
    static func keep(_ file: String, at t: Double, of d: Double, voice: Bool) {
        guard long(d, voice: voice) else { return }
        let ud = UserDefaults.standard
        var all = (ud.dictionary(forKey: key) as? [String: [Double]]) ?? [:]
        let was = all[file]
        all[file] = (t > 5 && t < d - 5) ? [t, Date().timeIntervalSince1970] : nil
        guard all[file] != was else { return }
        if all.count > most {
            let old = all.sorted { ($0.value.last ?? 0) < ($1.value.last ?? 0) }.prefix(all.count - most)
            for (k, _) in old { all[k] = nil }
        }
        ud.set(all, forKey: key)
    }
    static func at(_ file: String, of d: Double, voice: Bool) -> Double? {
        guard long(d, voice: voice), let t = ((UserDefaults.standard.dictionary(forKey: key) as? [String: [Double]])?[file])?.first,
              t > 5, t < d - 5 else { return nil }
        return t
    }
}

/// THE SOUND UNDER THE ONE PLAYER (25.09): a file on this phone sounds through the system's file player as it always has; a
/// track not yet whole sounds through the streaming player on its loader (MTStreams) — from the first pieces, a few seconds
/// buffered ahead. VoicePlayer speaks to both through this one shape; nothing else touches either.
protocol MTSound: AnyObject {
    var currentTime: TimeInterval { get set }
    var duration: TimeInterval { get }
    var isPlaying: Bool { get }
    var rate: Float { get set }
    var onEnd: (() -> Void)? { get set }
    @discardableResult func play() -> Bool
    func pause()
    func stop()
    /// THE COVER'S EAR (30.09): the meter stands on while the big cover listens (VoicePlayer.metering); the level of what sounds,
    /// 0 silence .. 1 full, read once a frame on the main thread and measured off it -- by the file player's own meter, by the
    /// audio tap under the stream (MTSoundEar).
    var metering: Bool { get set }
    func level() -> Float
}

final class MTFileSound: NSObject, MTSound, AVAudioPlayerDelegate {
    private let p: AVAudioPlayer
    var onEnd: (() -> Void)?
    init?(url: URL) {
        guard let p = try? AVAudioPlayer(contentsOf: url) else { return nil }
        self.p = p
        super.init()
        p.delegate = self
        p.enableRate = true
    }
    init?(data: Data) {
        guard let p = try? AVAudioPlayer(data: data) else { return nil }
        self.p = p
        super.init()
        p.delegate = self
        p.enableRate = true
    }
    var currentTime: TimeInterval { get { p.currentTime } set { p.currentTime = newValue } }
    var duration: TimeInterval { p.duration }
    var isPlaying: Bool { p.isPlaying }
    var rate: Float { get { p.rate } set { p.rate = newValue } }
    @discardableResult func play() -> Bool { p.play() }
    func pause() { p.pause() }
    func stop() { p.stop() }
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) { onEnd?() }
    var metering: Bool { get { p.isMeteringEnabled } set { p.isMeteringEnabled = newValue } }
    /// The platform's own meter of the file player: kept by its render thread, read here -- the channels' mean power.
    func level() -> Float {
        guard p.isMeteringEnabled, p.isPlaying else { return 0 }
        p.updateMeters()
        let n = p.numberOfChannels
        guard n > 0 else { return 0 }
        var sum: Float = 0
        for c in 0..<n { sum += p.averagePower(forChannel: c) }
        return MTSoundEar.unit(db: sum / Float(n))
    }
}

final class MTStreamSound: MTSound {
    private let p: AVPlayer
    private let item: AVPlayerItem
    private var endToken: NSObjectProtocol?
    private var wantRate: Float = 1
    var onEnd: (() -> Void)?
    init(asset: AVURLAsset) {
        item = AVPlayerItem(asset: asset)
        item.preferredForwardBufferDuration = 8   // a buffer, never the whole file (25.09)
        p = AVPlayer(playerItem: item)
        p.actionAtItemEnd = .pause
        endToken = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            self?.onEnd?()
        }
    }
    deinit { if let t = endToken { NotificationCenter.default.removeObserver(t) } }
    var currentTime: TimeInterval {
        get { let t = p.currentTime().seconds; return t.isFinite ? t : 0 }
        set { p.seek(to: CMTime(seconds: newValue, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) }
    }
    var duration: TimeInterval { let d = item.duration.seconds; return d.isFinite ? d : 0 }
    /// Playing, or waiting for its buffer to fill: the bar says «playing» while the first pieces come.
    var isPlaying: Bool { p.timeControlStatus != .paused }
    var rate: Float {
        get { wantRate }
        set { wantRate = newValue; if p.timeControlStatus != .paused { p.rate = newValue } }
    }
    @discardableResult func play() -> Bool { p.rate = wantRate; return true }   // the player starts once its buffer allows
    func pause() { p.pause() }
    func stop() { p.pause(); p.replaceCurrentItem(with: nil) }
    private var ear: MTSoundEar?
    var metering = false { didSet { if metering, ear == nil { listen() } } }
    func level() -> Float { metering && isPlaying ? MTSoundEar.unit(db: ear?.read() ?? -160) : 0 }
    /// The tap goes on the track's own audio once, the first time the cover listens, and stays for the item's life: the item's
    /// render chain is changed once, never under every opening of the cover.
    private func listen() {
        let e = MTSoundEar()
        ear = e
        let item = self.item
        Task { @MainActor in
            guard let track = try? await item.asset.loadTracks(withMediaType: .audio).first, let mix = e.mix(for: track) else {
                MontanaTrace.mark("cover_ear", "stream tap refused")
                return
            }
            item.audioMix = mix
        }
    }
}

/// THE STREAM'S EAR (30.09, the author's word ~01:45: «our icon sends out waves to the music's rhythm»): the level of what the
/// streaming player renders, measured on the platform's render thread by the audio tap on the track's own audio (the file player
/// keeps a meter of its own, MTFileSound.level). The render thread never waits for the main one: it hands its one word only when
/// the gate stands free (NSLock.try); the main thread reads it once a frame.
final class MTSoundEar {
    private let gate = NSLock()
    private var db: Float = -160
    fileprivate var float = false
    /// The level on the waves' scale: -40 dB and quieter is silence, 0 dB is full.
    static func unit(db: Float) -> Float { min(1, max(0, (db + 40) / 40)) }
    func read() -> Float {
        gate.lock()
        let v = db
        gate.unlock()
        return v
    }
    fileprivate func put(_ v: Float) {
        guard gate.try() else { return }
        db = v
        gate.unlock()
    }
    /// The track's mix with the tap: the tap holds the ear until the platform finalizes it.
    fileprivate func mix(for track: AVAssetTrack) -> AVAudioMix? {
        var calls = MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0,
            clientInfo: Unmanaged.passRetained(self).toOpaque(),
            init: { _, info, storage in storage.pointee = info },
            finalize: { tap in Unmanaged<MTSoundEar>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).release() },
            prepare: { tap, _, format in
                let f = format.pointee
                Unmanaged<MTSoundEar>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue().float =
                    f.mFormatFlags & kAudioFormatFlagIsFloat != 0 && f.mBitsPerChannel == 32
            },
            unprepare: nil,
            process: { tap, frames, _, list, framesOut, flagsOut in
                guard MTAudioProcessingTapGetSourceAudio(tap, frames, list, flagsOut, nil, framesOut) == noErr else { return }
                let ear = Unmanaged<MTSoundEar>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
                guard ear.float else { return }
                var sum: Float = 0
                var n = 0
                for b in UnsafeMutableAudioBufferListPointer(list) {
                    guard let d = b.mData?.assumingMemoryBound(to: Float.self) else { continue }
                    let k = Int(b.mDataByteSize) / 4
                    for i in 0..<k { sum += d[i] * d[i] }
                    n += k
                }
                guard n > 0 else { return }
                ear.put(10 * log10f(max(sum / Float(n), 1e-14)))
            })
        var tap: MTAudioProcessingTap?
        guard MTAudioProcessingTapCreate(kCFAllocatorDefault, &calls, kMTAudioProcessingTapCreationFlag_PostEffects, &tap) == noErr,
              let tap else {
            Unmanaged.passUnretained(self).release()
            return nil
        }
        let input = AVMutableAudioMixInputParameters(track: track)
        input.audioTapProcessor = tap
        let mix = AVMutableAudioMix()
        mix.inputParameters = [input]
        return mix
    }
}

// duration into the 0:07 format
/// A music file: the extensions the system player plays by itself. Decides the RENDER (a
/// player instead of a faceless document); the wire is untouched — the file rides as a doc,
/// as it did.
// The track's waveform on the shelf — the probing itself lives in the kit (MTWaveform.compute),
// where the share sheet probes too; here the shelf: memory, then the durable copy beside the
// pictures, so a bubble's first frame draws the bars on either side of the wire.
extension MTWaveform {
    private static let cache: NSCache<NSString, NSArray> = MontanaCaches.kept("waveforms")
    private static func fileURL(_ name: String) -> URL { MontanaPictures.url(name + ".wave") }

    /// What the shelf already holds — read in one move by the bubble's first frame.
    static func cached(_ name: String) -> [Float]? {
        if let c = cache.object(forKey: name as NSString) as? [Float] { return c }
        guard let d = try? Data(contentsOf: fileURL(name)), !d.isEmpty else { return nil }
        let s = unpack(d)
        cache.setObject(s as NSArray, forKey: name as NSString)
        return s
    }
    /// The shape kept by the file's name — from the manifest at receipt, from the probe at send.
    static func remember(_ name: String, _ s: [Float]) {
        cache.setObject(s as NSArray, forKey: name as NSString)
        try? pack(s).write(to: fileURL(name))
    }

    static func samples(_ name: String, bars: Int = MTWaveform.bars) async -> [Float]? {
        if let c = cached(name) { return c }
        let url = attachmentURL(name)
        let out: [Float]? = await Task.detached(priority: .utility) { compute(url, bars: bars) }.value
        if let out { remember(name, out) }
        return out
    }
}

let musicDurCache = NSCache<NSString, NSNumber>()
func musicFileDuration(_ name: String) -> Double {
    if let c = musicDurCache.object(forKey: name as NSString) { return c.doubleValue }
    let d = MontanaAudioDuration.of(attachmentURL(name))
    let v = d.isFinite ? d : 0
    musicDurCache.setObject(NSNumber(value: v), forKey: name as NSString)
    return v
}

func mtIsVideoName(_ name: String) -> Bool {
    ["mp4", "mov", "m4v"].contains((name as NSString).pathExtension.lowercased())
}
/// THE GALLERY OF A CONVERSATION (the author's word 11.09): every photo and every video that lies
/// on disk, in the feed's own order — the viewer pages through them as one; round notes stay out.
/// THE MOSAIC OF A MEDIA GROUP (19.09). Pure geometry: given the plate's ceiling and the pictures'
/// sizes it returns a rectangle and an edge position for every tile. Two, three and four pictures
/// take a fixed cut chosen by their shapes (wide / narrow / square-ish); five and more, or any very
/// wide picture, are laid in rows — every split into two, three or four rows of at most three tiles
/// is tried, and the one whose height comes nearest to four thirds of the width wins, a heavier top
/// row and a too-low row counting against it. Tiles stand one point apart. Nothing here touches a view.
enum MTMosaic {
    static let gap: CGFloat = 1
    struct Position: OptionSet {
        let rawValue: Int
        static let top = Position(rawValue: 1), bottom = Position(rawValue: 2)
        static let left = Position(rawValue: 4), right = Position(rawValue: 8)
        static let inside = Position(rawValue: 16)
    }
    struct Tile { var rect: CGRect; var position: Position }

    // The key, the slot and the ceiling of a group live in MTMediaGroup (MontanaMediaKit) — the one
    // owner the share sheet compiles as well ([C-1], 20.09). The cut below only draws what it is given.
    /// What folds into a plate: a picture or a video; a round note, a voice, a file and a sticker do not.
    static func folds(_ m: Message) -> Bool {
        if m.docName == MontanaCardPlate.stickerName { return false }
        if m.imageFile != nil { return true }
        if let v = m.videoFile { return !v.hasPrefix("vnote_") }
        return false
    }
    /// The picture's own shape for the cut: the decoded picture, the video's poster, the video's
    /// track, else a square — the manifest preview already shapes a picture still on its way.
    static func size(of m: Message) -> CGSize {
        // THE SHAPE IS ASKED OF THE HEADER, NEVER OF THE PIXELS (28.09): this runs in the body of a group's cell,
        // on the main thread, once per picture on the plate -- and it used to DECODE every photograph whole.
        if let f = m.imageFile, let s = pictureAspect(f), s != .zero { return s }
        if let v = m.videoFile {
            if let t = videoThumbCached(v), t.size != .zero { return t.size }
            if let a = videoAspect(v), a != .zero { return a }
        }
        return CGSize(width: 1, height: 1)
    }
    /// The corners of a tile: an outer corner is the plate's (the plate's shape cuts it), an inner
    /// corner — one that meets another tile — is a small rounding.
    static func corners(_ p: Position, inner: CGFloat = 3) -> RectangleCornerRadii {
        RectangleCornerRadii(topLeading: p.contains(.top) && p.contains(.left) ? 0 : inner,
                             bottomLeading: p.contains(.bottom) && p.contains(.left) ? 0 : inner,
                             bottomTrailing: p.contains(.bottom) && p.contains(.right) ? 0 : inner,
                             topTrailing: p.contains(.top) && p.contains(.right) ? 0 : inner)
    }

    static func layout(maxSize: CGSize, sizes: [CGSize]) -> (tiles: [Tile], size: CGSize) {
        let n = sizes.count
        guard n > 0 else { return ([], .zero) }
        let W = maxSize.width, H = maxSize.height, g = gap
        var shape = ""          // one letter per picture: w wide, n narrow, q square-ish
        var ratios: [CGFloat] = []
        var average: CGFloat = 0
        var stretched = false   // a very wide picture forces the row cut
        for s in sizes {
            let r = s.height > 0 ? s.width / s.height : 1
            shape += r > 1.2 ? "w" : (r < 0.8 ? "n" : "q")
            if r > 2 { stretched = true }
            average += r
            ratios.append(r)
        }
        average /= CGFloat(n)
        let minW: CGFloat = 68, minH: CGFloat = 81
        let plateRatio = W / H
        var tiles = Array(repeating: Tile(rect: .zero, position: []), count: n)
        if n == 1 {
            let h = floor(min(H, W / ratios[0]))
            tiles[0] = Tile(rect: CGRect(x: 0, y: 0, width: W, height: h), position: [.top, .bottom, .left, .right])
        } else if !stretched && n == 2 {
            if shape == "ww" && average > 1.4 * plateRatio && abs(ratios[1] - ratios[0]) < 0.2 {
                let h = floor(min(W / ratios[0], min(W / ratios[1], (H - g) / 2)))
                tiles[0] = Tile(rect: CGRect(x: 0, y: 0, width: W, height: h), position: [.top, .left, .right])
                tiles[1] = Tile(rect: CGRect(x: 0, y: h + g, width: W, height: h), position: [.bottom, .left, .right])
            } else if shape == "ww" || shape == "qq" {
                let w = (W - g) / 2
                let h = floor(min(w / ratios[0], min(w / ratios[1], H)))
                tiles[0] = Tile(rect: CGRect(x: 0, y: 0, width: w, height: h), position: [.top, .left, .bottom])
                tiles[1] = Tile(rect: CGRect(x: w + g, y: 0, width: w, height: h), position: [.top, .right, .bottom])
            } else {
                let second = floor(min(0.5 * (W - g), round((W - g) / ratios[0] / (1 / ratios[0] + 1 / ratios[1]))))
                let first = W - second - g
                let h = floor(min(H, round(min(first / ratios[0], second / ratios[1]))))
                tiles[0] = Tile(rect: CGRect(x: 0, y: 0, width: first, height: h), position: [.top, .left, .bottom])
                tiles[1] = Tile(rect: CGRect(x: first + g, y: 0, width: second, height: h), position: [.top, .right, .bottom])
            }
        } else if !stretched && n == 3 {
            if shape.hasPrefix("n") {
                let firstH = H
                let thirdH = min((H - g) * 0.5, round(ratios[1] * (W - g) / (ratios[2] + ratios[1])))
                let secondH = H - thirdH - g
                let rightW = max(minW, min((W - g) * 0.5, round(min(thirdH * ratios[2], secondH * ratios[1]))))
                let leftW = round(min(firstH * ratios[0], W - g - rightW))
                tiles[0] = Tile(rect: CGRect(x: 0, y: 0, width: leftW, height: firstH), position: [.top, .left, .bottom])
                tiles[1] = Tile(rect: CGRect(x: leftW + g, y: 0, width: rightW, height: secondH), position: [.right, .top])
                tiles[2] = Tile(rect: CGRect(x: leftW + g, y: secondH + g, width: rightW, height: thirdH), position: [.right, .bottom])
            } else {
                let firstH = floor(min(W / ratios[0], (H - g) * 0.66))
                tiles[0] = Tile(rect: CGRect(x: 0, y: 0, width: W, height: firstH), position: [.top, .left, .right])
                let w = (W - g) / 2
                let secondH = min(H - firstH - g, round(min(w / ratios[1], w / ratios[2])))
                tiles[1] = Tile(rect: CGRect(x: 0, y: firstH + g, width: w, height: secondH), position: [.left, .bottom])
                tiles[2] = Tile(rect: CGRect(x: w + g, y: firstH + g, width: w, height: secondH), position: [.right, .bottom])
            }
        } else if !stretched && n == 4 {
            if shape.hasPrefix("w") {
                let h0 = round(min(W / ratios[0], (H - g) * 0.66))
                tiles[0] = Tile(rect: CGRect(x: 0, y: 0, width: W, height: h0), position: [.top, .left, .right])
                var h = round((W - 2 * g) / (ratios[1] + ratios[2] + ratios[3]))
                let w0 = max(minW, min((W - 2 * g) * 0.4, h * ratios[1]))
                let w2 = max(max(minW, (W - 2 * g) * 0.33), h * ratios[3])
                let w1 = W - w0 - w2 - 2 * g
                h = max(minH, min(H - h0 - g, h))
                tiles[1] = Tile(rect: CGRect(x: 0, y: h0 + g, width: w0, height: h), position: [.left, .bottom])
                tiles[2] = Tile(rect: CGRect(x: w0 + g, y: h0 + g, width: w1, height: h), position: [.bottom])
                tiles[3] = Tile(rect: CGRect(x: w0 + w1 + 2 * g, y: h0 + g, width: w2, height: h), position: [.right, .bottom])
            } else {
                let h = H
                let w0 = round(min(h * ratios[0], (W - g) * 0.6))
                tiles[0] = Tile(rect: CGRect(x: 0, y: 0, width: w0, height: h), position: [.top, .left, .bottom])
                var w = round((H - 2 * g) / (1 / ratios[1] + 1 / ratios[2] + 1 / ratios[3]))
                let h0 = floor(w / ratios[1]), h1 = floor(w / ratios[2])
                let h2 = h - h0 - h1 - 2 * g
                w = max(minW, min(W - w0 - g, w))
                tiles[1] = Tile(rect: CGRect(x: w0 + g, y: 0, width: w, height: h0), position: [.right, .top])
                tiles[2] = Tile(rect: CGRect(x: w0 + g, y: h0 + g, width: w, height: h1), position: [.right])
                tiles[3] = Tile(rect: CGRect(x: w0 + g, y: h0 + h1 + 2 * g, width: w, height: h2), position: [.right, .bottom])
            }
        } else {
            // The row cut: every picture is brought to a shape near square (a wide set crops the
            // narrow ones, a narrow set the wide ones), then the rows are tried.
            let cropped: [CGFloat] = ratios.map { r in
                let c = average > 1.1 ? max(1, r) : min(1, r)
                return max(0.66667, min(1.7, c))
            }
            func rowHeight(_ rs: ArraySlice<CGFloat>) -> CGFloat { (W - CGFloat(rs.count - 1) * g) / rs.reduce(0, +) }
            var attempts: [(counts: [Int], heights: [CGFloat])] = []
            func add(_ counts: [Int]) {
                var start = 0; var hs: [CGFloat] = []
                for c in counts { hs.append(rowHeight(cropped[start..<start + c])); start += c }
                attempts.append((counts, hs))
            }
            for a in 1..<n { let b = n - a; if a > 3 || b > 3 { continue }; add([a, b]) }
            if n >= 3 {
                for a in 1..<(n - 1) { for b in 1..<(n - a) {
                    let c = n - a - b
                    if a > 3 || b > (average < 0.85 ? 4 : 3) || c > 3 { continue }
                    add([a, b, c])
                } }
            }
            if n >= 4 {
                for a in 1..<(n - 2) { for b in 1..<(n - a - 1) { for c in 1..<(n - a - b) {
                    let d = n - a - b - c
                    if a > 3 || b > 3 || c > 3 || d > 3 { continue }
                    add([a, b, c, d])
                } } }
            }
            let target = floor(W / 3 * 4)
            var best: (counts: [Int], heights: [CGFloat])? = nil
            var bestDiff: CGFloat = 0
            for a in attempts {
                var total = g * CGFloat(a.heights.count - 1)
                var lowest: CGFloat = .greatestFiniteMagnitude
                for h in a.heights { total += floor(h); lowest = min(lowest, floor(h)) }
                var diff = abs(total - target)
                let c = a.counts
                if c.count > 1, (c[0] > c[1]) || (c.count > 2 && c[1] > c[2]) || (c.count > 3 && c[2] > c[3]) { diff *= 1.5 }
                if lowest < minW { diff *= 1.5 }
                if best == nil || diff < bestDiff { best = a; bestDiff = diff }
            }
            if let best {
                var index = 0
                var y: CGFloat = 0
                for (i, count) in best.counts.enumerated() {
                    let lineH = ceil(best.heights[i])
                    var x: CGFloat = 0
                    var row: Position = []
                    if i == 0 { row.insert(.top) }
                    if i == best.counts.count - 1 { row.insert(.bottom) }
                    for k in 0..<count {
                        var pos = row
                        if k == 0 { pos.insert(.left) }
                        if k == count - 1 { pos.insert(.right) }
                        if row.isEmpty { pos = .inside }
                        let w = ceil(cropped[index] * lineH)
                        tiles[index] = Tile(rect: CGRect(x: x, y: y, width: w, height: lineH), position: pos)
                        x += w + g
                        index += 1
                    }
                    y += lineH + g
                }
                // The last tile of every row reaches the widest row's edge: the plate is a rectangle.
                var widest: CGFloat = 0
                index = 0
                for count in best.counts { index += count; widest = max(widest, tiles[index - 1].rect.maxX) }
                index = 0
                for count in best.counts {
                    index += count
                    var r = tiles[index - 1].rect
                    r.size.width = max(r.width, widest - r.minX)
                    tiles[index - 1].rect = r
                }
            }
        }
        var size = CGSize.zero
        for t in tiles {
            size.width = max(size.width, round(t.rect.maxX))
            size.height = max(size.height, round(t.rect.maxY))
        }
        return (tiles, size)
    }
}

/// The on-screen rectangles of a plate's tiles, so the plate's one tap finds the tile under the finger.
final class MTTileFrames {
    private var rects: [MID: CGRect] = [:]
    func set(_ id: MID, _ r: CGRect) { rects[id] = r }
    func rect(for id: MID) -> CGRect { rects[id] ?? .zero }
}

/// SAVED TO THE LIBRARY — the notebook and the one road (the author's word 11.09): the badge on a
/// picture asks here, saves here, and a saved name shows no badge again.
enum MontanaSavedToPhotos {
    private static let key = "savedToPhotos"
    static func has(_ f: String) -> Bool { (UserDefaults.standard.stringArray(forKey: key) ?? []).contains(f) }
    private static func note(_ f: String) {
        var a = UserDefaults.standard.stringArray(forKey: key) ?? []
        a.append(f); if a.count > 4000 { a.removeFirst(a.count - 4000) }
        UserDefaults.standard.set(a, forKey: key)
    }
    static func save(_ f: String, video: Bool) async -> Bool {
        let url = MontanaMediaVault.playableURL(f) ?? attachmentURL(f)
        let img = video ? nil : docImage(f)
        let ok: Bool = await withCheckedContinuation { c in
            PHPhotoLibrary.shared().performChanges({
                if video { PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url) }
                else if let img { PHAssetChangeRequest.creationRequestForAsset(from: img) }
            }) { done, _ in c.resume(returning: done) }
        }
        if ok { note(f) }
        MontanaTrace.mark("save_photos", "ok=\(ok ? 1 : 0) video=\(video ? 1 : 0)")
        return ok
    }
}
/// THE RECORDINGS ON THE SHELF GO TO PHOTOS (MontanaScreenShelf): at the launch and at every return the app lays each whole
/// movie the broadcast left into Photos with its own right (the platform asks once), and lets the shelf's copy go only when
/// Photos says it holds it.
enum MTScreenShelfTake {
    @MainActor private static var busy = false
    @MainActor static func run() {
        let movies = MontanaScreenShelf.movies()
        guard !movies.isEmpty, !busy else { return }
        busy = true
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { access in
            guard access == .authorized || access == .limited else {
                MontanaTrace.mark("screen_shelf", "photos add access=\(access.rawValue) waiting=\(movies.count)")
                Task { @MainActor in busy = false }
                return
            }
            for movie in movies {
                PHPhotoLibrary.shared().performChanges({
                    PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: movie)   // the road MontanaSavedToPhotos takes
                }) { held, _ in
                    if held { try? FileManager.default.removeItem(at: movie) }
                    MontanaTrace.mark("screen_shelf", "laid=\(held ? 1 : 0) name=\(movie.lastPathComponent.prefix(24))")
                }
            }
            Task { @MainActor in busy = false }
        }
    }
}
// mtIsAudioName lives in MontanaMediaKit — one definition, both targets ([C-1]).

func fmtDuration(_ s: Double) -> String {
    let total = Int(s.rounded())
    return String(format: "%d:%02d", total / 60, total % 60)
}

// load a photo file by name (we rebuild the path — it's stable across launches)
let imageDecodeCache: NSCache<NSString, UIImage> = MontanaCaches.kept("photos-decoded")
// The decoded photo is cached (the file name is unique per message) — otherwise disk+decode
// on EVERY bubble render = stutter during scroll/typing. preparingForDisplay prepares the bitmap
// in advance (not on the main thread during scroll),.
// SSOT of WHERE a picture reference is looked for on disk, in order. docImage decodes what this finds;
// a list only needs to know whether it is there at all, and both must not walk their own order.
/// Bytes for display. A correspondence file lies READY (MontanaMediaStore), so one thing
/// remains here: serve it. The legacy of older builds — attachments sealed in the archive —
/// moves into the store on first access, one by one and only what fits in memory.
enum MontanaMediaVault {
    private static let legacyLimit = 24 * 1024 * 1024   // BOUND-OK: larger legacy is not taken into memory

    static func data(_ name: String) -> Data? {
        guard !name.isEmpty else { return nil }
        if let u = mtMediaFileURL(name), let d = try? Data(contentsOf: u, options: .mappedIfSafe) { return d }
        guard MontanaArchive.mediaSize(blobId: name) <= legacyLimit,
              let d = MontanaArchive.findMedia(blobId: name) else { return nil }
        MontanaMediaStore.put(name, data: d)   // legacy migration: the next view will be instant
        return d
    }

    static func image(_ name: String) -> UIImage? { data(name).flatMap { UIImage(data: $0) } }

    /// The path for the player and the viewer. A finished file is served as is — any size.
    static func playableURL(_ name: String) -> URL? {
        if let u = mtMediaFileURL(name) { return u }
        guard MontanaArchive.mediaSize(blobId: name) <= legacyLimit,
              let d = MontanaArchive.findMedia(blobId: name),
              MontanaMediaStore.put(name, data: d) else { return nil }
        return MontanaMediaStore.url(name)
    }

    /// Open copies left by the previous storage scheme — off the disk.
    static func sweepStale() {
        let tmp = FileManager.default.temporaryDirectory
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: tmp.path) else { return }
        for n in names where n.hasPrefix("play_") {
            try? FileManager.default.removeItem(at: tmp.appendingPathComponent(n))
        }
    }
}

/// Disk cleanup — ONE place ([C-1]): both on return from background and on cold launch.
///
/// While every pass hung on the «became active» event, cold launch cleaned nothing: the
/// event does not always come, and the person saw the app open with the litter untouched.
enum MontanaHousekeeping {
    private static let lock = NSLock()
    private static var lastRun = Date.distantPast

    static func run() {
        lock.lock()
        let due = Date().timeIntervalSince(lastRun) > 30
        if due { lastRun = Date() }
        lock.unlock()
        guard due else { return }   // SILENT-OK: the cleanup just ran, a second pass has nothing to do
        // THE CLEANUP DOES NOT STAND ON THE LAUNCH ROAD. It walks thousands of files and
        // renames folders; on the main thread at the very moment of opening it took away both
        // the globe's speed to green and the peer's instant name — the app was busy with
        // litter instead of connection. Now it waits for the screen to come alive and works
        // aside.
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 4) {
            MontanaMediaVault.sweepStale()
            E2E.shared.sealArchiveFolderNames()
            E2E.shared.sweepBlobs()
            E2E.shared.sweepMediaFiles()
            E2E.shared.sweepOrphanPipes()
            sweepRetiredDoor()
        }
    }
    /// A RETIRED DOOR LEAVES NOTHING BEHIND (the author's word 03.10): the record a former sign-in kept on this device -- its
    /// folder and its key -- goes at the first run that no longer carries the door; every run after finds nothing to do.
    private static func sweepRetiredDoor() {
        E2EKeychain.delete("mt.outer.dbkey")
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Montana").appendingPathComponent("Outer")
        guard FileManager.default.fileExists(atPath: dir.path) else { return }
        let gone = (try? FileManager.default.removeItem(at: dir)) != nil
        MontanaTrace.mark("housekeeping", "retired_door_swept=\(gone ? 1 : 0)")
    }
}

/// WHERE A CORRESPONDENCE FILE LIVES ([C-1] — one place, one copy).
///
/// The author's rule: a file already in the chat must be ready to open — no assembly, no
/// waiting, any size. So it lies on disk READY. Earlier attempts to keep it sealed ran into
/// the core decrypting only whole files: three hundred megabytes do not fit in memory, and
/// there was nothing to open with.
///
/// Ready does not mean unguarded. The folder is chosen so that:
///   • it is NOT visible in Files or over the wire (only Documents is exposed);
///   • it is excluded from the backup — files do not travel to the OS vendor;
///   • every file gets the system disk-protection class «after first unlock»: until the
///     first unlock after power-on the file cannot be read by anything. The stricter class
///     (unavailable whenever the screen locks) would close background reception, so
///     this is the one that stands here — named for what it is.
/// The honest boundary: this is device-key protection, not seed protection. Seed encryption of
/// media without losing instant playback needs chunked reads in the core — separate work; the
/// storage will not need changing for it.
enum MontanaMediaStore {
    private static var dirCache: URL?
    static var dir: URL {
        if let c = dirCache { return c }
        let d = makeDir(); dirCache = d; return d
    }
    private static func makeDir() -> URL {
        var d = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Montana", isDirectory: true)
            .appendingPathComponent("Media", isDirectory: true)
        if !FileManager.default.fileExists(atPath: d.path) {
            try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true,
                                                     attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        }
        // The «skip the backup» flag is checked, not set once: a failure while creating the
        // folder would leave it in the backup FOREVER, and nobody would ever know.
        if (try? d.resourceValues(forKeys: [.isExcludedFromBackupKey]))?.isExcludedFromBackup != true {
            var rv = URLResourceValues(); rv.isExcludedFromBackup = true
            try? d.setResourceValues(rv)
        }
        return d
    }
    static func url(_ name: String) -> URL { dir.appendingPathComponent(name) }
    static func exists(_ name: String) -> Bool {
        !name.isEmpty && FileManager.default.fileExists(atPath: url(name).path)
    }

    @discardableResult
    static func put(_ name: String, data: Data) -> Bool {
        let ok = (try? data.write(to: url(name), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])) != nil
        if ok { MTNameBook.forgetPictures() }   // a picture file appeared — the name book asks the disk afresh (15.14)
        return ok
    }

    /// An accepted file MOVES out of the temporary folder rather than being copied: a copy of
    /// three hundred megabytes is both an extra minute and an extra three hundred megabytes
    /// on disk that same instant.
    @discardableResult
    static func adopt(from tmp: URL, name: String) -> Bool {
        let dst = url(name)
        // The finished file is NOT torn down in advance: the name derives from the letter id,
        // a repeat reception targets the same file, and between the teardown and a failed move
        // the working copy used to vanish. Replacement happens in one action or not at all.
        if FileManager.default.fileExists(atPath: dst.path) {
            guard (try? FileManager.default.replaceItemAt(dst, withItemAt: tmp)) != nil else { return false }
            stampArrival(dst)
            return true
        }
        guard (try? FileManager.default.moveItem(at: tmp, to: dst)) != nil else { return false }
        stampArrival(dst)
        return true
    }
    /// A FILE ENTERS THE STORE BORN NOW (the critic 24.09). The cleanup spares a newborn by the birth the disk names
    /// (newborn), and a file moved, copied or linked in carries the birth of its source: a track poured from a folder
    /// was born years ago to the cleanup, and a cleanup whose list of the living was taken a moment before the track's
    /// row was born carried it off; a forward's link wears its original's birth the same way. Every door of the store
    /// stamps the arrival — the protection class with it.
    private static func stampArrival(_ dst: URL) {
        let now = Date()
        try? FileManager.default.setAttributes([.creationDate: now, .modificationDate: now,
                                                .protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                                               ofItemAtPath: dst.path)
    }

    static func remove(_ names: [String]) {
        for n in names where !n.isEmpty {
            try? FileManager.default.removeItem(at: url(n))
            MontanaVideoMark.unmark(n)   // the «transcoded» mark has no life past its file
        }
    }
    /// THE SAME BYTES UNDER A SECOND NAME (20.09): a forward is a letter of its own and wears a file
    /// of its own — a hard link, so no byte is doubled and either row may lose its file alone.
    /// A store that cannot link (a foreign volume) copies; a name already taken is left as it is.
    @discardableResult
    static func clone(_ name: String, as fresh: String) -> Bool {
        guard exists(name), !fresh.isEmpty, fresh != name else { return false }
        if exists(fresh) { return true }
        if (try? FileManager.default.linkItem(at: url(name), to: url(fresh))) != nil { stampArrival(url(fresh)); return true }
        guard (try? FileManager.default.copyItem(at: url(name), to: url(fresh))) != nil else { return false }
        stampArrival(url(fresh))
        return true
    }
    static func names() -> Set<String> {
        Set((try? FileManager.default.contentsOfDirectory(atPath: dir.path))?.filter { !$0.hasPrefix(".") } ?? [])
    }

    /// WHAT A HAND IS STILL HOLDING (the critic 22.09). A file lands on disk the instant a picture
    /// is pasted or picked; the letter that will NAME it is born only when the arrow is pressed --
    /// seconds or minutes later. The cleanup reads «named by a letter» as «needed», so for that
    /// whole while an attachment is litter by construction. Measured on T1 at 16:17:18: the sweep
    /// carried a pasted photograph off 0.3 s before the send, the row was born over bytes that no
    /// longer existed, and every retry walked into the same wall («the file is gone, the intent
    /// goes»). The composer says what it holds and the cleanup counts it among the living.
    /// Memory only, never disk: a hold dies with the process, so a screen that failed to release
    /// one cannot keep a file for ever.
    private static var holds = Set<String>()
    private static let holdLock = NSLock()
    static func hold(_ names: [String]) {
        let fresh = names.filter { !$0.isEmpty }
        guard !fresh.isEmpty else { return }
        holdLock.lock(); holds.formUnion(fresh); holdLock.unlock()
    }
    static func release(_ names: [String]) {
        guard !names.isEmpty else { return }
        holdLock.lock(); holds.subtract(names); holdLock.unlock()
    }
    static var held: Set<String> {
        holdLock.lock(); defer { holdLock.unlock() }; return holds
    }

    /// How long a newborn file is spared by the cleanup. It covers the MECHANICAL gap between the
    /// bytes landing and the row naming them -- milliseconds on every road -- not the time a person
    /// spends composing, which the hold above covers. A wider window cannot be bought here: a
    /// single deleted letter leaves its file to this very cleanup, so this window is also how long
    /// an erased picture outlives its bubble. Sixty seconds lies inside the delay the cleanup
    /// already carries (it runs four seconds after the screen wakes, at most once in thirty).
    static let newbornGrace: TimeInterval = 60

    /// A file's age, asked of the disk at the moment the folder is listed, so nothing can age
    /// between the question and the answer. A file whose birth cannot be read counts as newborn:
    /// a cleanup that cannot date what it carries off does not carry it off.
    static func newborn(_ name: String) -> Bool {
        guard let v = try? url(name).resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey]),
              let born = v.creationDate ?? v.contentModificationDate else { return true }
        return Date().timeIntervalSince(born) < newbornGrace
    }
}

func mtMediaFileURL(_ s: String) -> URL? {
    let fm = FileManager.default
    if s.hasPrefix("/") {
        return fm.fileExists(atPath: s) ? URL(fileURLWithPath: s) : nil
    }
    if MontanaMediaStore.exists(s) { return MontanaMediaStore.url(s) }   // the correspondence's finished file
    let candidates = [mediaTmpURL(s),                                                        // legacy: the temporary folder
                      avatarsDirURL().appendingPathComponent(s),                             // avatars
                      fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
                        .appendingPathComponent(s)]                                          // legacy
    return candidates.first { fm.fileExists(atPath: $0.path) }
}

// Is there a picture behind this reference at all — a bundled asset, a remote address, or a file.
// No decoding: this runs for every row of a list on every pass.
func mtPictureExists(_ ref: String) -> Bool {
    if ref.isEmpty { return false }
    if ref.hasPrefix("http") { return true }
    if UIImage(named: ref) != nil { return true }
    return mtMediaFileURL(ref) != nil
}

/// The decoded picture if it is already in the cache — no disk, no decode; nil says «not yet».
func docImageCached(_ s: String) -> UIImage? {
    guard let c = imageDecodeCache.object(forKey: s as NSString), c.size != .zero else { return nil }
    return c
}
func docImage(_ s: String) -> UIImage? {
    if let c = imageDecodeCache.object(forKey: s as NSString) {
        if c.size != .zero { return c }
        // A REFUSAL IS A MOMENT, NOT A VERDICT (29.09, the iPhone 17 at 13:16Z: a picture just sent stood grey for the life
        // of the process while the same file opened in the viewer -- the «no file» word, once written, was never asked
        // again). The word stands only while no file lies here; a file that lies here is read afresh.
        guard mtMediaFileURL(s) != nil else { return nil }
        imageDecodeCache.removeObject(forKey: s as NSString)
    }
    var raw: UIImage?
    if let url = mtMediaFileURL(s) { raw = UIImage(contentsOfFile: url.path) }
    // The file moved between the ask and the read (the store adopts a file out of the temporary folder): asked once more where it lies now.
    if raw == nil, let url = mtMediaFileURL(s) { raw = UIImage(contentsOfFile: url.path) }
    if raw == nil { raw = MontanaMediaVault.image(s) }   // no open copy on disk — take it from the archive
    if raw == nil, !s.hasPrefix("/"), let d = try? Data(contentsOf: posterURL(s)), let p = UIImage(data: d) {
        // The file is still downloading — serve the manifest preview. The frame's shape is
        // right at once, sharpness arrives with the file itself. The preview is NOT cached as
        // final: otherwise the blurry picture would remain after the download.
        return p
    }
    guard let img = raw else {
        if mtMediaFileURL(s) != nil {
            // The file lies here and the decoder gave nothing: written, never remembered -- the next ask reads the file again.
            MontanaTrace.markFolded("picture_refused", "name=\(String(s.prefix(20))) -- the file lies here, the decoder gave nothing", window: 30, key: s)
            return nil
        }
        imageDecodeCache.setObject(UIImage(), forKey: s as NSString)   // "no file" marker — not asked again until a file lies here
        return nil
    }
    let ready = img.preparingForDisplay() ?? img
    imageDecodeCache.setObject(ready, forKey: s as NSString)
    return ready
}

// ── ATTACHMENTS: videos and files ──────────────────────────────────
// path to an attachment file in the documents folder (by name)
// Ephemeral media folder (tmp) — invisible in "Files", cleaned by the OS; permanent storage — sealed in Montana/Chats/<chat>/Media/.
func mediaTmpURL(_ name: String) -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(name) }
enum MontanaAudioDuration { static func of(_ url: URL) -> Double { CMTimeGetSeconds(AVURLAsset(url: url).duration) } }
func voiceRecordURL(_ name: String) -> URL { mediaTmpURL(name) }   // recorder writes into the temporary folder, not the Documents root
/// The path to a correspondence file — ONE ladder for the whole client ([C-1]).
///
/// The finished-file store appeared and this function never learned of it — half the client
/// kept looking for attachments in the empty temporary folder: photo and voice sends fell
/// into «failed», music had a dead button and 0:00, «Share» silently would not open. Where a
/// file lives is asked HERE, and nowhere else.
func attachmentURL(_ name: String) -> URL {
    if let lent = MTMusicFolders.url(name) { return lent }         // a lent folder's track lies in its folder (MTMusicFolders)
    if name.hasPrefix("/") { return URL(fileURLWithPath: name) }   // old absolute path
    if MontanaMediaStore.exists(name) { return MontanaMediaStore.url(name) }
    let tmp = mediaTmpURL(name)
    if FileManager.default.fileExists(atPath: tmp.path) { return tmp }
    return docsURL().appendingPathComponent(name)                  // fallback for old files
}

// save arbitrary data into documents, return the file name
func saveToDocs(_ data: Data, ext: String) -> String? {
    let name = "att_\(UUID().uuidString).\(ext)"
    return MontanaMediaStore.put(name, data: data) ? name : nil
}

// copy the selected file into documents; return (name on disk, original name)
func copyToDocs(from src: URL, original: String) -> (String, String)? {
    let ext = (original as NSString).pathExtension.isEmpty ? src.pathExtension : (original as NSString).pathExtension
    let stored = "att_\(UUID().uuidString)\(ext.isEmpty ? "" : ".\(ext)")"
    let dest = mediaTmpURL(stored)   // tmp, not the Documents root (permanent storage — sealed vault)
    // need to open access to the file from "Files" (iCloud/external providers)
    let needsScope = src.startAccessingSecurityScopedResource()
    defer { if needsScope { src.stopAccessingSecurityScopedResource() } }
    do {
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.copyItem(at: src, to: dest)
        return (stored, original)
    } catch { return nil }
}

// human-readable file size: "1.3 MB"
func fileSizeString(_ name: String) -> String {
    let path = attachmentURL(name).path
    let attrs = try? FileManager.default.attributesOfItem(atPath: path)
    let size = (attrs?[.size] as? Int) ?? 0
    return Int64(size).formatted(.byteCount(style: .file).locale(MTLanguage.locale))   // the unit in the app's one language
}

// Video frame preview. CRITICAL: generation ONLY off-main (copyCGImage is a synchronous
// AVAsset decode; on main it froze the feed), and failure is CACHED with a UIImage() marker
// (a broken/missing file would otherwise be re-decoded on every render = permanent freeze).
let videoThumbCache: NSCache<NSString, UIImage> = MontanaCaches.kept("video-posters")
// The bubble's GEOMETRY comes from the video itself (metadata, no decoding): the poster is
// born asynchronously, and for its first moments the bubble fell to a 4:3 placeholder —
// a vertical video stood horizontal through the whole compression phase and flipped at
// upload (precedent 23.08 01:50). One geometry source, correct from the first render.
/// A PICTURE'S SHAPE, WITHOUT ITS PIXELS (28.09, measured on T1 under 1966: a chat opened with one frame of
/// 637 ms on the main thread -- motion what=chat:open late_cells=637ms/group1+photo1+text2+voice1 -- and the plate
/// of a media group asked each of its pictures for its size by decoding the whole photograph right there in the
/// cell's body). A file's own header carries width, height and orientation, and reading them decodes nothing. The
/// law the video's geometry has kept since 23.08 (videoAspect below), now for pictures too.
let pictureAspectCache = NSCache<NSString, NSValue>()
func pictureAspect(_ name: String) -> CGSize? {
    if let v = pictureAspectCache.object(forKey: name as NSString) { return v.cgSizeValue }
    if let c = docImageCached(name), c.size != .zero {
        pictureAspectCache.setObject(NSValue(cgSize: c.size), forKey: name as NSString)
        return c.size
    }
    // A picture still on its way wears the shape of the manifest's preview; one that lies only in the archive
    // wears its small copy's (the one road a row's picture has taken since 16.09). Neither decodes a photograph.
    if mtMediaFileURL(name) == nil {
        if let d = try? Data(contentsOf: posterURL(name)), let pv = UIImage(data: d), pv.size != .zero {
            return pv.size   // the preview is not remembered: the file itself will answer differently
        }
        guard let small = MontanaSmallPicture.image(name), small.size != .zero else { return nil }
        pictureAspectCache.setObject(NSValue(cgSize: small.size), forKey: name as NSString)
        return small.size
    }
    guard let url = mtMediaFileURL(name),
          let src = CGImageSourceCreateWithURL(url as CFURL, nil),
          let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
          let w = (props[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
          let h = (props[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue,
          0 < w, 0 < h else { return nil }
    // The orientations from the fifth on stand the picture on its side: the sides swap with them.
    let turned = 5 <= ((props[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1)
    let sz = turned ? CGSize(width: h, height: w) : CGSize(width: w, height: h)
    pictureAspectCache.setObject(NSValue(cgSize: sz), forKey: name as NSString)
    return sz
}
let videoAspectCache = NSCache<NSString, NSValue>()
func videoAspect(_ name: String) -> CGSize? {
    if let v = videoAspectCache.object(forKey: name as NSString) { return v.cgSizeValue }
    let url = attachmentURL(name)
    guard FileManager.default.fileExists(atPath: url.path),
          let t = AVURLAsset(url: url).tracks(withMediaType: .video).first else { return nil }
    let o = t.naturalSize.applying(t.preferredTransform)
    let sz = CGSize(width: abs(o.width), height: abs(o.height))
    guard sz.width > 0, sz.height > 0 else { return nil }
    videoAspectCache.setObject(NSValue(cgSize: sz), forKey: name as NSString)
    return sz
}
let videoThumbQueue = DispatchQueue(label: "montana.videothumb", qos: .userInitiated)
// A failed frame generation is a MOMENT, not a verdict: while hardware encoders chew a long
// video the frame decoder refuses for a while, and caching that refusal forever painted
// every bubble black until restart (precedent 23.08: «sometimes black screens on all
// videos»). The cooldown lets the next attempt retry once the squeeze passes.
let videoThumbFailAt = NSCache<NSString, NSDate>()
func videoThumbCached(_ name: String) -> UIImage? {
    // A round note's own frame first, once it was made -- its own book (MTNoteFrame), which no writer of
    // the letter's preview reaches; the letter's preview until then.
    if name.hasPrefix("vnote_"), let f = MTNoteFrame.cached(name) { return f }
    if let c = videoThumbCache.object(forKey: name as NSString), c.size != .zero { return c }
    // The poster lies on disk from the letter's birth: reading it here (a small jpeg, once —
    // the cache holds it after) keeps the frame AND the aspect present from the very first
    // render. The bubble never flips from a square placeholder to the real shape (the
    // author's rule 23.08: one thumbnail, correct aspect, always).
    if let d = try? Data(contentsOf: posterURL(name)), let img = UIImage(data: d), img.size != .zero {
        videoThumbCache.setObject(img, forKey: name as NSString)
        return img
    }
    return nil
}
// A frame from the video for the manifest thumbnail.
func videoPosterImage(_ url: URL) -> UIImage? {
    let gen = AVAssetImageGenerator(asset: AVURLAsset(url: url))
    gen.appliesPreferredTrackTransform = true
    gen.maximumSize = CGSize(width: 640, height: 640)
    guard let cg = try? gen.copyCGImage(at: posterMoment(url.lastPathComponent, gen), actualTime: nil) else { return nil }
    return UIImage(cgImage: cg)
}

/// EVERY SMALL PICTURE IN A ROW IS BORN SMALL ([C-1], the author's word 16.09: faces and thumbnails
/// jumped and stood crooked at opening). A row used to draw a face by decoding the whole photograph
/// off the main thread — the initial first, the face a frame later — and a photo's thumbnail by
/// decoding the whole photograph on the main thread. One road now: a small copy (192 px, made by
/// the system's own thumbnailer with the picture's orientation applied) lies beside the file on
/// disk from its first request and is decoded in a fraction of a millisecond on the first frame.
/// Nothing is drawn twice; nothing waits.
enum MontanaSmallPicture {
    static let side: CGFloat = 192
    private static let cache: NSCache<NSString, UIImage> = MontanaCaches.kept("small-pictures")
    private static func smallURL(_ name: String) -> URL { MontanaPictures.url(name + ".small.jpg") }
    /// The picture's file changed under its name: the small copy is made afresh on the next ask.
    static func forget(_ name: String) {
        cache.removeObject(forKey: name as NSString)
        try? FileManager.default.removeItem(at: smallURL(name))
    }
    static func image(_ name: String) -> UIImage? {
        if let c = cache.object(forKey: name as NSString) { return c }
        if let d = try? Data(contentsOf: smallURL(name)), let ui = UIImage(data: d) {
            cache.setObject(ui, forKey: name as NSString); return ui
        }
        // The file on disk, or the legacy one moved out of the archive into the store on this ask.
        guard let src = mtMediaFileURL(name) ?? MontanaMediaVault.playableURL(name), let made = thumbnail(src) else { return nil }
        if let d = made.jpegData(compressionQuality: 0.85) { try? d.write(to: smallURL(name)) }
        cache.setObject(made, forKey: name as NSString)
        return made
    }
    private static func thumbnail(_ url: URL) -> UIImage? {
        guard let s = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                     kCGImageSourceThumbnailMaxPixelSize: side,
                                     kCGImageSourceCreateThumbnailWithTransform: true,
                                     kCGImageSourceShouldCacheImmediately: true]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(s, 0, opts as CFDictionary) else { return nil }
        return UIImage(cgImage: cg)
    }
}

/// THE PICTURES' OWN HOME (the author's word 16.09: «from local memory, at once, as it should
/// be»): the posters and the small copies used to lie in the app's temporary folder, and the
/// system clears that folder while the app is not running — after a reopening the list drew
/// glyphs where the pictures had stood the day before. They live beside the media store now,
/// in Application Support, excluded from the backup, under the same disk protection; nothing
/// sweeps this folder by name. A picture found still in the temporary folder is moved in once.
enum MontanaPictures {
    private static var dirCache: URL?
    static var dir: URL {
        if let c = dirCache { return c }
        let d = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Montana", isDirectory: true)
            .appendingPathComponent("Pictures", isDirectory: true)
        if !FileManager.default.fileExists(atPath: d.path) {
            try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true,
                                                     attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        }
        if (try? d.resourceValues(forKeys: [.isExcludedFromBackupKey]))?.isExcludedFromBackup != true {
            var rv = URLResourceValues(); rv.isExcludedFromBackup = true
            var m = d; try? m.setResourceValues(rv)
        }
        dirCache = d
        return d
    }
    static func url(_ file: String) -> URL {
        let u = dir.appendingPathComponent(file)
        // The one-time move from the temporary folder where the older builds kept it.
        if !FileManager.default.fileExists(atPath: u.path) {
            let old = mediaTmpURL(file)
            if FileManager.default.fileExists(atPath: old.path) { try? FileManager.default.moveItem(at: old, to: u) }
        }
        return u
    }
}

// The poster = the manifest thumbnail laid on disk beside the future file.
// The bubble shows it at once, before the file itself downloads.
func posterURL(_ name: String) -> URL { MontanaPictures.url(name + ".poster.jpg") }

/// A ROUND NOTE'S PICTURE IS A FRAME OF ITS OWN FILE (the author's word 23.09: «the note's miniature in the chat must be
/// sharp and beautiful, as a photo — now it is a blurred mess»). A note is born with the letter's small preview (320 px,
/// 12 KB — the same bytes on both sides, all a letter can carry), and that preview was the circle's picture for the
/// note's whole life, stretched over some 800 pixels of a three-times screen. Once the file itself lies on this phone —
/// the sender's at once, the receiver's the moment it lands — the circle wears the file's own frame at its full size,
/// kept beside the preview under its own name; the preview stays what the letter carries. A note is square on every
/// side, so the two chats keep one shape and only the sharpness grows. A dual note's frame is the one its poster
/// names (posterMoment), the small circle in it.
///
/// THE FRAME IS A BOOK OF ITS OWN, AND THE CIRCLE ASKS UNTIL IT WEARS IT (the author's word 24.09: «the sender's
/// circles are sharp, in the new style; the receiver's are the old blurred ones»). Two holes let the blur back.
/// The frame shared one cache with the letter's preview, and the send road writes that preview into the same
/// cache under the same name, so a send or a resend after the frame was worn covered it with the blur again.
/// And the circle stopped asking at its first picture: a single refusal of the decoder -- it refuses while a
/// call or an encoder holds it (23.08) -- handed back the preview, and the preview stood on the circle for the
/// bubble's whole life. The frame now lives in its own book (memory over its file), read first by every reader
/// of a note's picture, and the circle asks until the frame is worn (wear).
enum MTNoteFrame {
    static func url(_ name: String) -> URL { MontanaPictures.url(name + ".frame.jpg") }
    private static let frames: NSCache<NSString, UIImage> = MontanaCaches.kept("note-frames")
    /// The frame, once it was made: from memory, else from its file (then kept in memory).
    static func cached(_ name: String) -> UIImage? {
        if let f = frames.object(forKey: name as NSString) { return f }
        guard let d = try? Data(contentsOf: url(name)), let img = UIImage(data: d), img.size != .zero else { return nil }
        frames.setObject(img, forKey: name as NSString)
        return img
    }
    /// Made on the thumbnail queue, from the file at its own size; nil while the file is not here or while
    /// its decoder refuses -- the refusal is written, and the circle asks again.
    static func make(_ name: String) -> UIImage? {
        let file = attachmentURL(name)
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        let gen = AVAssetImageGenerator(asset: AVURLAsset(url: file))
        gen.appliesPreferredTrackTransform = true
        let cg: CGImage
        do { cg = try gen.copyCGImage(at: posterMoment(name, gen), actualTime: nil) } catch {
            MontanaTrace.markFolded("note_frame", "refused err=\((error as NSError).code) -- the preview stands, the circle asks again",
                                       window: 60, key: name)
            return nil
        }
        let img = UIImage(cgImage: cg)
        // Memory first, the file whole or not at all: a reader on the screen's thread never meets half a picture.
        frames.setObject(img, forKey: name as NSString)
        try? img.jpegData(compressionQuality: 0.92)?.write(to: url(name), options: .atomic)
        MontanaTrace.markFolded("note_frame", "made px=\(cg.width)", window: 30)
        return img
    }
    /// THE CIRCLE ASKS UNTIL IT WEARS ITS FRAME. The letter's preview is a picture to draw, never the end of
    /// the asking while the note's file lies here: the asking goes on at a growing pause, one second to thirty.
    /// It ends when the frame is worn, when the file is not here yet (its landing changes the asker's key and
    /// the asking begins again), after five empty answers, or when the view that asked goes. The view is
    /// redrawn when a picture first comes and when the frame comes -- not at every ask.
    static func wear(_ name: String, redraw: @MainActor () -> Void) async {
        var drawn = false, empty = 0
        var pause: UInt64 = 1
        while !Task.isCancelled {
            let img = await videoThumbAsync(name)
            if cached(name) != nil { await redraw(); return }
            if img == nil {
                empty += 1
                if empty == 5 { return }
            } else {
                if !drawn { drawn = true; await redraw() }
                if !fileOnDisk(name) { return }
            }
            try? await Task.sleep(nanoseconds: pause * 1_000_000_000)
            pause = min(pause * 2, 30)
        }
    }
    /// The note left: its frame goes with it.
    static func forget(_ name: String) {
        frames.removeObject(forKey: name as NSString)
        try? FileManager.default.removeItem(at: url(name))
    }
}

/// THE FRAME IS BORN WITH THE FILE, NOT WITH THE SEND (the critic 22.09, measured on the author's
/// iPhone 17 at 17:57 over cellular). A row stood in the chat 26 ms after the finger — and stood
/// EMPTY for sixteen seconds: «row_thumb kind=vid src=none» at its birth, the picture only at
/// «compress END». The frame was made inside the send, in a task started the same instant as the
/// encoder, and the two fought over one video engine while the person looked at a grey plate of
/// a file already lying on his own phone.
///
/// The library keeps a frame of every video of its own and hands it over at once — the platform's
/// own mechanism, asked for here instead of decoding a three-hundred-megabyte source a second time.
/// One owner for the poster's birth: the send road's own block finds the file already written and
/// does nothing, so nothing is done twice and nothing is decided in two places ([C-1]).
enum MontanaVideoPoster {
    /// The manifest's recipe, so the bubble, the row and the letter all wear ONE set of bytes.
    static func keep(_ name: String, _ img: UIImage) {
        guard let d = img.mediaThumbnail(maxDim: 320, maxBytes: 12_000) else {
            MontanaTrace.mark("poster", "REFUSED name=\(String(name.prefix(20))) — the frame could not be shrunk")
            return
        }
        do {
            try d.write(to: posterURL(name))
        } catch {
            MontanaTrace.mark("poster", "REFUSED name=\(String(name.prefix(20))) — the frame could not be written")
            return
        }
        if let small = UIImage(data: d) { videoThumbCache.setObject(small, forKey: name as NSString) }
    }

    /// The library's own frame for a picked video, under the name the row will wear. Off the main
    /// thread by contract: the caller stands on a background callback already. A refusal SPEAKS —
    /// the silent `return` on this path is exactly why nobody could see where the picture went.
    static func fromLibrary(_ asset: PHAsset, as name: String) {
        if FileManager.default.fileExists(atPath: posterURL(name).path) { return }
        let t0 = Date()
        let opts = PHImageRequestOptions()
        // THE ROW NEVER WAITS FOR A NETWORK. A synchronous request makes the library ignore the
        // delivery mode and serve the full quality, and with network access allowed an asset that
        // lives only in the cloud would hold this thread for as long as the download takes — the
        // very wait this whole change exists to remove. Local only: no frame here simply means the
        // frame comes from the file a moment later, and the row still never stands empty.
        opts.isNetworkAccessAllowed = false
        opts.deliveryMode = .fastFormat
        opts.isSynchronous = true              // the caller stands on a background callback, never the screen's thread
        opts.resizeMode = .fast
        var picked: UIImage?
        PHImageManager.default().requestImage(for: asset,
                                              targetSize: CGSize(width: 640, height: 640),
                                              contentMode: .aspectFit,
                                              options: opts) { img, _ in picked = img }
        guard let picked else {
            MontanaTrace.mark("poster", "name=\(String(name.prefix(20))) — no local frame in the library, taking it from the file")
            ensure(name)
            return
        }
        keep(name, picked)
        MontanaTrace.mark("poster", "library frame name=\(String(name.prefix(20))) ms=\(Int(Date().timeIntervalSince(t0) * 1000))")
    }

    /// A clip STAGED above the field, with no library asset behind it: the frame comes from the file
    /// itself, while nothing yet holds the video engine. Off the main thread by contract, as fromLibrary:
    /// the caller stands on a background callback, and the frame is on disk BEFORE the attachment is
    /// handed to the screen (24.09, the whole library under limited access) — the first drawing has it.
    static func fromFile(_ name: String) {
        if FileManager.default.fileExists(atPath: posterURL(name).path) { return }
        let t0 = Date()
        let url = attachmentURL(name)
        guard FileManager.default.fileExists(atPath: url.path), let img = videoPosterImage(url) else {
            MontanaTrace.mark("poster", "REFUSED name=\(String(name.prefix(20))) — no frame from the file")
            return
        }
        keep(name, img)
        MontanaTrace.mark("poster", "file frame name=\(String(name.prefix(20))) ms=\(Int(Date().timeIntervalSince(t0) * 1000))")
    }
    /// The same frame asked from any thread: it is taken on a thread of its own.
    static func ensure(_ name: String) {
        if FileManager.default.fileExists(atPath: posterURL(name).path) { return }
        Task.detached(priority: .userInitiated) { fromFile(name) }
    }
}

func fileOnDisk(_ name: String) -> Bool {
    FileManager.default.fileExists(atPath: attachmentURL(name).path)
}

func videoThumbAsync(_ name: String) async -> UIImage? {
    // A round note is answered by its own frame (MTNoteFrame); until the frame is made the note is asked on
    // the queue every time -- the letter's preview in the shared cache is never a note's last word.
    let note = name.hasPrefix("vnote_")
    if note, let f = MTNoteFrame.cached(name) { return f }
    if !note, let c = videoThumbCache.object(forKey: name as NSString) { return c.size == .zero ? nil : c }
    return await withCheckedContinuation { cont in
        videoThumbQueue.async {
            if note, let f = MTNoteFrame.cached(name) { cont.resume(returning: f); return }
            if !note, let c = videoThumbCache.object(forKey: name as NSString) {
                cont.resume(returning: c.size == .zero ? nil : c); return
            }
            if let f = videoThumbFailAt.object(forKey: name as NSString),
               Date().timeIntervalSince(f as Date) < 5 { cont.resume(returning: nil); return }
            // A note whose file is not here yet, or whose decoder refused: the letter's preview stands (below),
            // and the circle asks again (MTNoteFrame.wear).
            if note, let img = MTNoteFrame.make(name) { cont.resume(returning: img); return }
            // SSOT: the poster IS the bubble image for its whole life. Decoding a frame
            // from the file produced a THIRD variant of the same thumbnail (900 px vs the
            // 320 px the manifest carries) and the bubble visibly switched mid-flight.
            if let d = try? Data(contentsOf: posterURL(name)), let img = UIImage(data: d), img.size != .zero {
                videoThumbCache.setObject(img, forKey: name as NSString)
                cont.resume(returning: img); return
            }
            var out: UIImage?
            let url = attachmentURL(name)
            if FileManager.default.fileExists(atPath: url.path) {
                let gen = AVAssetImageGenerator(asset: AVURLAsset(url: url))
                gen.appliesPreferredTrackTransform = true
                gen.maximumSize = CGSize(width: 900, height: 900)
                if let cg = try? gen.copyCGImage(at: posterMoment(name, gen), actualTime: nil) {
                    out = UIImage(cgImage: cg)
                }
            }
            if let out {
                videoThumbCache.setObject(out, forKey: name as NSString)
                let poster = posterURL(name)
                if !FileManager.default.fileExists(atPath: poster.path) {
                    try? out.jpegData(compressionQuality: 0.7)?.write(to: poster)
                }
            } else { videoThumbFailAt.setObject(NSDate(), forKey: name as NSString) }
            cont.resume(returning: out)
        }
    }
}

// video preview in the media grid (chat profile)
struct VideoGridThumb: View {
    let file: String
    @State private var img: UIImage?
    var body: some View {
        ZStack {
            if let i = img { Image(uiImage: i).resizable().scaledToFill() } else { Color.black }
        }
        .task(id: file) { img = await videoThumbAsync(file) }
    }
}

// video from the gallery → a copy in the app's documents
struct ChatMovie: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            // tmp, NOT the Documents root: permanent storage — only sealed in Montana/Chats/<chat>/Media/
            let dest = mediaTmpURL("att_\(UUID().uuidString).mov")
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.copyItem(at: received.file, to: dest)
            return ChatMovie(url: dest)
        }
    }
}

// the latest photos/videos from the phone gallery (for the feed in the attachments panel)
final class RecentMedia: NSObject, ObservableObject, PHPhotoLibraryChangeObserver {
    @Published var assets: [PHAsset] = []
    @Published var status: PHAuthorizationStatus = .notDetermined
    private var loaded = false
    private var observing = false

    /// HOW DEEP THE READING GOES. The strip of the «+» plate needs the last few dozen; the gallery
    /// page is scrolled down into older days (the author word 22.09) and asks for more. The number
    /// only ever grows, and a growth re-reads the library once.
    private(set) var depth = 60
    func want(_ n: Int) {
        guard n > depth else { return }
        depth = n
        guard status == .authorized || status == .limited else { return }
        // Never on the screen's thread: six hundred picture objects are made here (22.09).
        DispatchQueue.global(qos: .userInitiated).async { self.fetch() }
    }
    /// THE LIBRARY IS READ BEFORE THE FINGER ASKS FOR IT (the author's word 22.09: «the first time
    /// it shows no photographs, only the second time»). The whole chain — the permission answer, the
    /// fetch, the making of six hundred picture objects — used to begin at the touch on the gallery,
    /// and the page opened onto an empty grid while it ran. The chat warms it at its own opening,
    /// WITHOUT ever asking for permission here: the status is read, not requested, so nobody is
    /// shown a dialog for opening a conversation. If the answer was never given, the page itself
    /// asks (load), as it always did.
    func warm() {
        let st = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard st == .authorized || st == .limited else { return }
        loaded = true
        DispatchQueue.main.async { self.status = st }
        if !observing { observing = true; PHPhotoLibrary.shared().register(self) }
        DispatchQueue.global(qos: .userInitiated).async { self.fetch() }
    }
    /// A page opening again re-reads what the library holds now — cheap, and never a stale list.
    func refresh() {
        guard status == .authorized || status == .limited else { return }
        DispatchQueue.global(qos: .userInitiated).async { self.fetch() }
    }
    func load() {
        guard !loaded else { return }
        loaded = true
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
            DispatchQueue.main.async { self.status = status }
            guard status == .authorized || status == .limited else { return }
            if !self.observing { self.observing = true; PHPhotoLibrary.shared().register(self) }
            self.fetch()
        }
    }
    // the limited selection changed (the user added photos via "Select more") → re-read the feed
    func photoLibraryDidChange(_ changeInstance: PHChange) {
        DispatchQueue.main.async { self.fetch() }
    }
    deinit { if observing { PHPhotoLibrary.shared().unregisterChangeObserver(self) } }
    func fetch() {
        let opts = PHFetchOptions()
        opts.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        opts.fetchLimit = depth
        let result = PHAsset.fetchAssets(with: opts)
        var arr: [PHAsset] = []
        result.enumerateObjects { a, _, _ in arr.append(a) }
        DispatchQueue.main.async { self.assets = arr }
    }
    // Change the selection under limited access (sheet) → then re-read the feed
    func presentLimitedPicker() {
        guard let top = VideoPresenter.topVC() else { return }
        PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: top) { [weak self] _ in self?.fetch() }
    }
}

// a single media preview tile in the attachments feed
// ════════════════════════════════════════════════════════════
// ATTACHMENTS SHEET: "Recent" — a grid of photos/videos
// with selection circles, a "Send (N)" button and a bottom bar.
// ════════════════════════════════════════════════════════════
/// THE CAPTION STANDS ON THE KEYS (the author's word 22.09: «it falls under the keyboard»). The sheet's
/// own keyboard avoidance is not relied on for this bar: it is lifted by the ONE owner of the keyboard's
/// facts (MTKeyboard — height and up/down, the same numbers the emoji panel reads) in the keys' own spring
/// (MTKeyboardSpring), and the sheet's root ignores the keyboard region so nothing lifts it a second time.
/// No interactive drag lives in these sheets, so the announced move is the whole move. The bar's bottom
/// stands at the keys' top: the keyboard's height less the safe strip the bar already stands above.
private struct MTOnKeys: ViewModifier {
    @ObservedObject private var kb = MTKeyboard.shared
    func body(content: Content) -> some View {
        content
            .padding(.bottom, kb.isUp ? max(0, kb.height - MTScene.safeInsets().bottom) : 0)
            .animation(MTKeyboardSpring.swiftUI(speed: 1), value: kb.isUp)
    }
}

struct AttachSheet: View {
    @ObservedObject var recent: RecentMedia
    /// THE DRAFT BECOMES THE CAPTION (the author's word 19.09): words already typed in the field
    /// stand in the caption the moment the sheet opens; the person adds pictures to what was said.
    var initialCaption: String = ""
    var onSend: ([PHAsset], String) -> Void
    var onCamera: () -> Void
    var onGallery: () -> Void
    var onFile: () -> Void
    var onLocation: () -> Void
    var onContact: () -> Void
    var onCard: () -> Void = {}
    @Environment(\.dismiss) private var dismiss
    @State private var selected: [String] = []      // localIdentifier in selection order
    @State private var caption = ""
    @State private var previewAsset: PHAsset?
    @State private var albumPage = ""   // the page the album shows — sent when nothing is picked
    @StateObject private var assetImages = MTAssetImages()
    @State private var captionFocused = false   // the field's own focus (MTInputField's binding)
    /// The pictures by their names, put in a book once per answer of the library: a walk through the
    /// array for every tile the grid builds was a comparison per picture per tile (23.09).
    @State private var byId: [String: PHAsset] = [:]

    private var hasCamera: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }
    static let cameraId = "camera"   // the grid's first tile

    var body: some View {
        VStack(spacing: 0) {
            header
            // THE GRID IS THE PLATFORM'S (the author's word 19.09): the system's own photo grid manner —
            // the pinch decides how many frames stand in a row, a drag from a circle selects along the
            // tiles, the grid rolls itself at the edges; see MTTileGrid.
            MTTileGrid(ids: (hasCamera ? [Self.cameraId] : []) + recent.assets.map(\.localIdentifier),
                       selected: $selected, fixed: [Self.cameraId]) { id in
                if id == Self.cameraId {
                    MTCameraTile(action: { onCamera() })
                } else if let a = byId[id] {
                    SelectableThumb(asset: a, order: selected.firstIndex(of: id),
                                    onPreview: { previewAsset = a }, onToggle: { toggle(a) })
                }
            } prefetch: { ids in MTAssetImages.preheat(ids.compactMap { byId[$0] }) }
                .overlay {
                    if recent.assets.isEmpty && !hasCamera {
                        Text("No access to photos").foregroundColor(.gray).font(.subheadline)
                    }
                }
            bottomBar
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)   // the caption is lifted once, by MTOnKeys — never twice
        .background(Color.black.ignoresSafeArea())
        .onAppear {
            recent.load(); take(recent.assets)
            if caption.isEmpty { caption = initialCaption }
        }
        .onChange(of: recent.assets) { _, a in take(a) }
        // THE ALBUM IS THE ALBUM (the author's word 11.09): a photo opened from the picker is
        // the same viewer the chat's photos open into — the strip, the swipes, the zoom — with
        // the pick's order at the top right; the circle there is the grid's circle.
        // IT RISES FROM BELOW WITH THE CAPTION AND THE SEND (the author's word 12.09): under the
        // album stand the caption field and the send button — pick in the album, write, send,
        // with no way back through the grid. Send with nothing picked sends the page on screen.
        .sheet(item: $previewAsset) { a in albumSheet(a) }
    }

    func albumSheet(_ a: PHAsset) -> some View {
        VStack(spacing: 0) {
            MontanaPhotoViewer(image: assetImages.page(a.localIdentifier),
                               files: recent.assets.map(\.localIdentifier), startFile: a.localIdentifier,
                               loader: { assetImages.page($0) }, coverLoader: { assetImages.cover($0) },
                               videoOf: { id in recent.assets.first { $0.localIdentifier == id }?.mediaType == .video },
                               play: { id in if let a = recent.assets.first(where: { $0.localIdentifier == id }) { MTAssetImages.play(a) } },
                               order: { selected.firstIndex(of: $0) },
                               onToggle: { id in if let a = recent.assets.first(where: { $0.localIdentifier == id }) { toggle(a) } },
                               onPage: { albumPage = $0 }) {
                previewAsset = nil
            }
            captionBar {
                var picked = pickedAssets()
                if picked.isEmpty, let cur = recent.assets.first(where: { $0.localIdentifier == albumPage }) { picked = [cur] }
                send(picked)
            }
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)   // the caption is lifted once, by MTOnKeys — never twice
        .background(Color.black.ignoresSafeArea())
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        .presentationBackground(Color.black)
    }

    /// The one road out: the caption is taken, the sheets fold, the letters leave.
    private func send(_ picked: [PHAsset]) {
        let cap = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        previewAsset = nil
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { onSend(picked, cap) }
    }

    var header: some View {
        ZStack {
            Text(selected.isEmpty ? "Recent" : "Selected: \(selected.count)")
                .font(.headline).bold().foregroundColor(.white)
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.system(size: 15, weight: .semibold)).foregroundColor(.white)
                        .frame(width: 34, height: 34).background(Color(white: 0.22), in: Circle())
                        .montanaFingerRoom(layout: 34)
                }
                Spacer()
                if recent.status == .limited {
                    // compact "Manage" in the corner: select more / change settings
                    Menu {
                        Button("Choose other photos") { recent.presentLimitedPicker() }
                        Button("Change settings") { MontanaSystemSettings.open() }   // the one door: it warns under a call (24.09)
                    } label: {
                        Image(systemName: "ellipsis").font(.system(size: 17, weight: .semibold)).foregroundColor(Color.accentColor)
                            .frame(width: 34, height: 34).background(Color(white: 0.22), in: Circle())
                    }
                }
            }
        }
        .padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 10)
    }

    @ViewBuilder var bottomBar: some View {
        if selected.isEmpty {
            HStack(spacing: 0) {
                toolItem("Gallery", "photo.fill.on.rectangle.fill", active: true) { onGallery() }
                toolItem("Business card", "person.text.rectangle.fill") { onCard() }
                toolItem("File", "doc.fill") { onFile() }
                toolItem("Location", "location.fill") { onLocation() }
                toolItem("Contact", "person.crop.circle.fill") { onContact() }
            }
            .padding(.top, 8).padding(.bottom, 4)
            .background(Color(white: 0.07))
        } else {
            captionBar { send(pickedAssets()) }
        }
    }

    /// The caption field and the send button — one bar for the grid and for the album: the chat's own
    /// field (MTComposeRow, the author's word 22.09). Its frame is in the diary («caption-bar» beside
    /// kb_show): where it stands when the keys are up is measured, not assumed.
    func captionBar(send: @escaping () -> Void) -> some View {
        MTComposeRow(text: $caption, focused: $captionFocused, placeholder: "Caption…", onSend: send)
            .background(Color(white: 0.07))
            .background(MTFrameMark("caption-bar"))
            .modifier(MTOnKeys())
    }

    func toolItem(_ title: LocalizedStringKey, _ icon: String, active: Bool = false, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 22))
                Text(title).font(.caption2)
            }
            .foregroundColor(active ? Color.accentColor : .gray)
            .frame(maxWidth: .infinity)
        }
    }

    private func take(_ assets: [PHAsset]) {
        assetImages.hold(assets)
        byId = Dictionary(assets.map { ($0.localIdentifier, $0) }, uniquingKeysWith: { a, _ in a })
    }
    func toggle(_ a: PHAsset) {
        if let i = selected.firstIndex(of: a.localIdentifier) { selected.remove(at: i) }
        else { selected.append(a.localIdentifier) }
    }
    func pickedAssets() -> [PHAsset] {
        selected.compactMap { byId[$0] }
    }
}

/// THE PICTURES OF THE PICKER, ONE CACHE for the grid's covers and the album's pages (the
/// author's word 11.09): a cover is asked at 300, a page at 1400; a page not yet decoded is
/// requested and the cache publishes when it lands; only the last few pages are kept.
final class MTAssetImages: ObservableObject {
    // THE COVERS ARE THE PLATFORM'S (23.09, the author: «choosing media, it stutters as I scroll»).
    // Every tile used to observe this one object, so each cover that landed woke EVERY tile and the
    // page above them, and the page re-applied the grid's whole snapshot of six hundred names; the
    // library's opportunistic mode lands every cover twice, and during a scroll they land without
    // pause. The covers were asked of the plain manager with no preheating, with iCloud allowed, and
    // kept without a bound — six hundred of 300 px, about 200 MB (T1 died on screen at 233 MB).
    // Now the covers come from the platform's own PHCachingImageManager, preheated by the grid's own
    // prefetching, local only; they live in one bounded cache, and a tile holds its own picture
    // (MTAssetCover), so a landing cover redraws that tile and nothing else.
    static let caching: PHCachingImageManager = {
        let m = PHCachingImageManager(); m.allowsCachingHighQualityImages = false; return m
    }()
    static let coverPx = CGSize(width: 360, height: 360)
    static let coverCache: NSCache<NSString, UIImage> = MontanaCaches.kept("gallery-covers", count: 300)
    static var coverOptions: PHImageRequestOptions {
        let o = PHImageRequestOptions()
        o.deliveryMode = .opportunistic
        o.resizeMode = .fast
        o.isNetworkAccessAllowed = false   // a grid shows what the phone holds; the cloud is asked for a page, not a tile
        return o
    }
    /// The pictures the grid is about to show — the collection view's own prefetch names them.
    static func preheat(_ assets: [PHAsset]) {
        guard !assets.isEmpty else { return }
        caching.startCachingImages(for: assets, targetSize: coverPx, contentMode: .aspectFill, options: coverOptions)
    }
    /// One cover, delivered on the main thread; the degraded picture first, then the sharp one.
    @discardableResult
    static func requestCover(_ a: PHAsset, done: @escaping (UIImage) -> Void) -> PHImageRequestID {
        caching.requestImage(for: a, targetSize: coverPx, contentMode: .aspectFill, options: coverOptions) { img, info in
            guard let img else { return }
            let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
            if !degraded { coverCache.setObject(img, forKey: a.localIdentifier as NSString) }
            if Thread.isMainThread { done(img) } else { DispatchQueue.main.async { done(img) } }
        }
    }
    private var pages: [String: UIImage] = [:]
    private var order: [String] = []
    private var asked: Set<String> = []
    private static let keptPages = 6
    /// The assets by name, handed in from the list: a lookup in the library's own base per
    /// picture (fetchAssets by identifier) was a trip to the disk on every request.
    private var byId: [String: PHAsset] = [:]
    func hold(_ assets: [PHAsset]) { byId = Dictionary(assets.map { ($0.localIdentifier, $0) }, uniquingKeysWith: { a, _ in a }) }
    private func asset(_ id: String) -> PHAsset? { byId[id] }
    /// Pictures land in bursts; the screen is told once per turn of the loop, not once per picture.
    private var pendingPublish = false
    private func publish() {
        guard !pendingPublish else { return }
        pendingPublish = true
        DispatchQueue.main.async { self.pendingPublish = false; self.objectWillChange.send() }
    }
    /// The album's stand-in while its page decodes: the same bounded cache the tiles fill.
    func cover(_ id: String) -> UIImage? {
        if let c = Self.coverCache.object(forKey: id as NSString) { return c }
        guard !asked.contains("c:" + id), let a = asset(id) else { return nil }
        asked.insert("c:" + id)
        Self.requestCover(a) { [weak self] _ in self?.asked.remove("c:" + id); self?.publish() }
        return nil
    }
    func page(_ id: String) -> UIImage? {
        if let p = pages[id] { return p }
        request(id, size: 1400, key: "p:" + id) { [weak self] img in
            guard let self else { return }
            self.pages[id] = img
            self.order.removeAll { $0 == id }; self.order.append(id)
            while self.order.count > Self.keptPages, let old = self.order.first {
                self.order.removeFirst(); self.pages[old] = nil; self.asked.remove("p:" + old)
            }
            self.publish()
        }
        return cover(id)   // the cover stands in until the page lands
    }
    private func request(_ id: String, size: CGFloat, key: String, done: @escaping (UIImage) -> Void) {
        guard !asked.contains(key), let a = asset(id) else { return }
        asked.insert(key)
        let opts = PHImageRequestOptions()
        opts.deliveryMode = size > 400 ? .highQualityFormat : .opportunistic
        opts.isNetworkAccessAllowed = true
        PHImageManager.default().requestImage(for: a, targetSize: CGSize(width: size, height: size),
                                              contentMode: size > 400 ? .aspectFit : .aspectFill, options: opts) { img, _ in
            guard let img else { return }
            DispatchQueue.main.async { done(img) }
        }
    }
    /// A video of the library plays in the system player, as the chat's videos do.
    static func play(_ a: PHAsset) {
        let opts = PHVideoRequestOptions(); opts.isNetworkAccessAllowed = true
        PHImageManager.default().requestPlayerItem(forVideo: a, options: opts) { item, _ in
            guard let item else { return }
            DispatchQueue.main.async {
                MontanaAudioSession.activatePlayback()
                let c = AVPlayerViewController(); c.player = AVPlayer(playerItem: item)
                MTTop.present(c, kind: "library-video") { c.player?.play() }
            }
        }
    }
}

/// THE PICK CIRCLE, named once: the grid's tile and the album page wear the same one. The colour is
/// the page's to name (22.09): the picker of the compose row wears the platform's own tint, as the
/// examples the author gave do; everywhere else it stays the gold it has always been.
struct MTPickOrder: View {
    let order: Int?
    var tint: Color = .blue
    var ink: Color = .black
    var body: some View {
        ZStack {
            Circle().fill(order != nil ? tint : Color.black.opacity(0.28))
                .frame(width: 27, height: 27)
            Circle().strokeBorder(.white, lineWidth: 2).frame(width: 27, height: 27)
            if let order {
                Text("\(order + 1)").font(.system(size: 13, weight: .bold)).foregroundColor(ink)
            }
        }
    }
}

/// ONE GRID OF TILES ([C-1], the author's word 19.09): the picker's Recent and the app's gallery
/// stand on this one collection view, in the platform's own photo-grid manner — a compositional
/// layout of N columns; the pinch re-lays it with the system's own animation; and, when a selection
/// is handed in, a touch that begins on a tile's circle drags a selection along the tiles — the
/// scroll waits for that pan to fail, the platform's own rule — while the grid rolls itself when the
/// finger nears an edge. The tiles are whichever view the owner hands in, told the column count.
struct MTTileGrid: UIViewRepresentable {
    let ids: [String]
    var selected: Binding<[String]>? = nil   // the picker's order; nil — a grid nobody selects in
    var fixed: Set<String> = []              // tiles outside any selection or drag (the camera)
    /// THE CEILING IS THE GRID OWN (the critic 22.09): a tap could be counted by the page above, but
    /// a DRAG writes the order straight into the binding — a finger pulled across the tiles walked
    /// past any ten the page thought it held. The range stops at the ceiling here, where it is made.
    var limit: Int? = nil
    let tile: (String) -> AnyView            // the tile of an id; it reads its own size, not the column count
    /// The ids the collection view says it is about to show (its own prefetching) — the owner warms them.
    var prefetch: (([String]) -> Void)? = nil
    static let columnSteps = [1, 2, 3, 5, 8]
    init<T: View>(ids: [String], selected: Binding<[String]>? = nil, fixed: Set<String> = [],
                  limit: Int? = nil, @ViewBuilder tile: @escaping (String) -> T,
                  prefetch: (([String]) -> Void)? = nil) {
        self.ids = ids; self.selected = selected; self.fixed = fixed; self.limit = limit
        self.tile = { AnyView(tile($0)) }
        self.prefetch = prefetch
    }

    func makeUIView(context: Context) -> UICollectionView {
        let co = context.coordinator
        let cv = UICollectionView(frame: .zero, collectionViewLayout: MTTileGrid.layout(columns: co.columns))
        cv.backgroundColor = .black
        cv.alwaysBounceVertical = true
        co.attach(cv, view: self)
        cv.delegate = co                 // the gesture's frames are measured, as the chat's feed is
        cv.prefetchDataSource = co       // the platform names the tiles about to come
        cv.addGestureRecognizer(UIPinchGestureRecognizer(target: co, action: #selector(Coordinator.pinch(_:))))
        if selected != nil {
            let pan = UIPanGestureRecognizer(target: co, action: #selector(Coordinator.pan(_:)))
            pan.delegate = co
            pan.maximumNumberOfTouches = 1
            cv.addGestureRecognizer(pan)
            cv.panGestureRecognizer.require(toFail: pan)   // the scroll waits for the circle's pan to fail
        }
        return cv
    }
    func updateUIView(_ cv: UICollectionView, context: Context) {
        context.coordinator.view = self
        context.coordinator.apply()
    }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    static func layout(columns: Int) -> UICollectionViewCompositionalLayout {
        let gap: CGFloat = 2
        let item = NSCollectionLayoutItem(layoutSize: .init(widthDimension: .fractionalWidth(1.0 / CGFloat(columns)),
                                                            heightDimension: .fractionalHeight(1.0)))
        item.contentInsets = NSDirectionalEdgeInsets(top: gap / 2, leading: gap / 2, bottom: gap / 2, trailing: gap / 2)
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: .init(widthDimension: .fractionalWidth(1.0),
                                                                         heightDimension: .fractionalWidth(1.0 / CGFloat(columns))),
                                                       subitems: [item])
        return UICollectionViewCompositionalLayout(section: NSCollectionLayoutSection(group: group))
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate, UICollectionViewDelegate, UICollectionViewDataSourcePrefetching {
        var view: MTTileGrid
        var columns = 3
        private weak var cv: UICollectionView?
        private var ds: UICollectionViewDiffableDataSource<Int, String>?
        private var prints: [String: Int] = [:]
        private var appliedIds: [String] = []
        private var dragStart: String?
        private var dragMode = true
        private var dragBase: [String] = []
        private var roll: CADisplayLink?
        private var rollSpeed: CGFloat = 0
        private var transition: UICollectionViewTransitionLayout?   // the pinch's live re-lay, the platform's own
        private var transitionTo = 3
        init(_ v: MTTileGrid) { view = v }
        deinit { roll?.invalidate() }
        private var picked: [String] { view.selected?.wrappedValue ?? [] }
        func attach(_ cv: UICollectionView, view v: MTTileGrid) {
            self.cv = cv; view = v
            let reg = UICollectionView.CellRegistration<UICollectionViewCell, String> { [weak self] cell, _, id in
                guard let self else { return }
                cell.contentConfiguration = UIHostingConfiguration { self.view.tile(id) }.margins(.all, 0)
            }
            ds = UICollectionViewDiffableDataSource<Int, String>(collectionView: cv) { cv, ip, id in
                cv.dequeueConfiguredReusableCell(using: reg, for: ip, item: id)
            }
        }
        /// The rows in the owner's order; a tile is redrawn only when its place in the selection changed.
        func apply() {
            guard let ds else { return }
            // A snapshot refuses a repeated identifier with an abort (measured 18.09 23:51 on T1: one
            // file lying in two letters opened the gallery into a crash) — the first stands, the rest go.
            var seen = Set<String>()
            let ids = view.ids.filter { seen.insert($0).inserted }
            var fresh: [String: Int] = [:]
            for id in ids { fresh[id] = picked.firstIndex(of: id) ?? -1 }
            let changed = ids.filter { prints[$0] != nil && prints[$0] != fresh[$0] }
            prints = fresh
            // A page redrawn for any other reason leaves an unchanged grid alone (23.09): the snapshot
            // of six hundred names used to be re-applied on every redraw of the page above.
            if ids == appliedIds, changed.isEmpty { return }
            appliedIds = ids
            var snap = NSDiffableDataSourceSnapshot<Int, String>()
            snap.appendSections([0]); snap.appendItems(ids)
            if !changed.isEmpty { snap.reconfigureItems(changed) }
            ds.apply(snap, animatingDifferences: false)
        }
        func collectionView(_ cv: UICollectionView, prefetchItemsAt ips: [IndexPath]) {
            guard let f = view.prefetch, let ds else { return }
            f(ips.compactMap { ds.itemIdentifier(for: $0) })
        }
        func scrollViewWillBeginDragging(_ sv: UIScrollView) { MTFrameMeter.shared.begin(rows: view.ids.count, on: sv) }
        func scrollViewDidEndDragging(_ sv: UIScrollView, willDecelerate: Bool) { if !willDecelerate { MTFrameMeter.shared.end("gallery") } }
        func scrollViewDidEndDecelerating(_ sv: UIScrollView) { MTFrameMeter.shared.end("gallery") }
        /// THE PINCH IS LIVE, THE PLATFORM'S OWN WAY (the author's word 19.09: «as native as the
        /// system's grid»): the collection view's interactive layout transition — the grid re-lays
        /// itself UNDER the fingers, its progress the pinch's own scale (fingers parting: fewer
        /// columns; closing: more), and on release it finishes to the next count or falls back.
        /// No tile is rebuilt: the tiles stay, the platform moves them.
        @objc func pinch(_ g: UIPinchGestureRecognizer) {
            guard let cv else { return }
            switch g.state {
            case .changed:
                if transition == nil {
                    guard abs(g.scale - 1) > 0.04, let i = MTTileGrid.columnSteps.firstIndex(of: columns) else { return }
                    let j = g.scale > 1 ? i - 1 : i + 1
                    guard MTTileGrid.columnSteps.indices.contains(j) else { return }
                    transitionTo = MTTileGrid.columnSteps[j]
                    transition = cv.startInteractiveTransition(to: MTTileGrid.layout(columns: transitionTo)) { [weak self] _, _ in
                        self?.transition = nil
                    }
                }
                guard let t = transition else { return }
                let zoomingIn = transitionTo < columns
                let p = zoomingIn ? (g.scale - 1) / 0.6 : (1 - g.scale) / 0.4
                t.transitionProgress = max(0, min(1, p))
            case .ended, .cancelled, .failed:
                guard let t = transition else { return }
                if t.transitionProgress > 0.35 { columns = transitionTo; cv.finishInteractiveTransition() }
                else { cv.cancelInteractiveTransition() }
            default: break
            }
        }
        /// The drag begins only on a tile's circle corner; anywhere else the touch is the scroll's.
        /// THE TILE THE FINGER TOOK IS THE TILE IT PRESSED (the author's word 22.09: «the first photo
        /// does not answer the first press when I want to select many, and the choice falls on the
        /// rightmost one»). The start used to be read at the gesture's BEGIN — and a pan begins only
        /// after the platform's slop of about ten points, by which time the finger, starting on the
        /// circle at a tile's right edge, already stood over its NEIGHBOUR: the tile whose circle was
        /// pressed stayed unchosen and the drag opened on the next one — the last of the row when the
        /// press was on the tile before it. The press itself names the tile here, once, and the begin
        /// takes that name.
        private var pressedTile: String?
        func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
            guard g is UIPanGestureRecognizer, let cv else { return true }
            let p = g.location(in: cv)
            guard let ip = cv.indexPathForItem(at: p), let cell = cv.cellForItem(at: ip),
                  let id = ds?.itemIdentifier(for: ip), !view.fixed.contains(id) else { pressedTile = nil; return false }
            let corner = CGRect(x: cell.frame.maxX - 44, y: cell.frame.minY, width: 44, height: 44).contains(p)
            pressedTile = corner ? id : nil
            return corner
        }
        @objc func pan(_ g: UIPanGestureRecognizer) {
            guard let cv else { return }
            let p = g.location(in: cv)
            switch g.state {
            case .began:
                // The pressed tile first; the point under the finger only if the press named none.
                var start = pressedTile
                if start == nil, let ip = cv.indexPathForItem(at: p), let id = ds?.itemIdentifier(for: ip), !view.fixed.contains(id) { start = id }
                guard let id = start else { return }
                dragStart = id
                dragMode = !picked.contains(id)
                dragBase = picked
                applyRange(to: id)
            case .changed:
                if let ip = cv.indexPathForItem(at: p), let id = ds?.itemIdentifier(for: ip), !view.fixed.contains(id) {
                    applyRange(to: id)
                }
                let y = p.y - cv.contentOffset.y, h = cv.bounds.height
                rollSpeed = y > h - 70 ? 6 : (y < 70 ? -6 : 0)
                if rollSpeed != 0 { startRoll() } else { stopRoll() }
            default:
                dragStart = nil; pressedTile = nil; stopRoll()
            }
        }
        /// The range from the circle the drag began on to the tile under the finger takes the start
        /// tile's new state; a tile that leaves the range goes back to what it was before the drag.
        private func applyRange(to id: String) {
            guard let s = dragStart, let sel = view.selected else { return }
            let ids = view.ids.filter { !view.fixed.contains($0) }
            guard let ia = ids.firstIndex(of: s), let ib = ids.firstIndex(of: id) else { return }
            let range = Array(ids[min(ia, ib)...max(ia, ib)])
            var next = dragBase
            if dragMode { for x in range where !next.contains(x) { next.append(x) } }
            else { next.removeAll { range.contains($0) } }
            if let lim = view.limit, next.count > lim { next = Array(next.prefix(lim)) }   // the drag stops at the ceiling
            if next != sel.wrappedValue { sel.wrappedValue = next }
        }
        private func startRoll() {
            guard roll == nil else { return }
            let l = CADisplayLink(target: self, selector: #selector(rollTick))
            l.add(to: .main, forMode: .common); roll = l
        }
        private func stopRoll() { roll?.invalidate(); roll = nil }
        @objc private func rollTick() {
            guard let cv else { return }
            let top = -cv.adjustedContentInset.top
            let bottom = max(top, cv.contentSize.height - cv.bounds.height + cv.adjustedContentInset.bottom)
            cv.contentOffset.y = max(top, min(bottom, cv.contentOffset.y + rollSpeed))
        }
    }
}
/// The camera's tile — the first of the grid.
struct MTCameraTile: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Color(white: 0.16)
                .overlay {
                    VStack(spacing: 6) {
                        Image(systemName: "camera.fill").font(.system(size: 26))
                        Text("Camera").font(.caption2)
                    }
                    .foregroundColor(.white)
                }
        }
    }
}

/// A TILE HOLDS ITS OWN PICTURE (23.09): asked when the tile appears, cancelled when it leaves, so a
/// cover that lands redraws this tile alone. A recycled cell handed another picture starts clean
/// (the caller names the view by the picture).
struct MTAssetCover: View {
    let asset: PHAsset
    @State private var img: UIImage?
    @State private var request: PHImageRequestID?
    var body: some View {
        ZStack {
            if let img { Image(uiImage: img).resizable().scaledToFill() } else { Color(white: 0.16) }
        }
        .onAppear {
            if img == nil, let c = MTAssetImages.coverCache.object(forKey: asset.localIdentifier as NSString) { img = c; return }
            guard img == nil else { return }
            request = MTAssetImages.requestCover(asset) { i in img = i }
        }
        .onDisappear {
            if let r = request { MTAssetImages.caching.cancelImageRequest(r); request = nil }
        }
    }
}

// media tile in the grid with a selection circle (number when selected) and duration for videos
struct SelectableThumb: View {
    let asset: PHAsset
    let order: Int?          // position in the selection (nil = not selected)
    var tint: Color = .blue   // the circle's colour and the veil over a chosen tile
    var ink: Color = .black         // the number inside the circle
    var onPreview: () -> Void // tap on media → preview
    var onToggle: () -> Void  // tap on the circle → select/deselect

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay { MTAssetCover(asset: asset).id(asset.localIdentifier) }
            .clipped()
            .overlay { if order != nil { tint.opacity(0.22) } }
            .overlay(alignment: .bottomTrailing) {
                if asset.mediaType == .video {
                    Text(fmtDuration(asset.duration))
                        .font(.system(size: 11, weight: .semibold)).foregroundColor(.white)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Color.black.opacity(0.5), in: Capsule())
                        .padding(5)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { onPreview() }   // tap on the image → preview
            // selection circle — ON TOP, with its own tap (does not open the preview); the drag that
            // begins on it belongs to the grid's own pan (MTTileGrid), not to the tile.
            .overlay(alignment: .topTrailing) {
                MTPickOrder(order: order, tint: tint, ink: ink).padding(6).contentShape(Circle()).onTapGesture { onToggle() }
            }
    }
}

/// THE GALLERY OF THE COMPOSE ROW (the author word 22.09, by his own screenshots). A touch on the
/// gallery opens the phone own latest pictures as the platform lays them out — newest first, three
/// in a row, the pinch changing how many — chosen one at a time or by dragging the finger from a
/// circle across them, at most ten, the circle wearing the platform own tint and the number of the
/// choice. At the foot stand two buttons of our glass: the way back, and the whole library, which
/// opens THE PLATFORM OWN picker with its collections, its search and its own ten. (Those two carry
/// words because the author asked for these very buttons; the rule of wordless buttons holds
/// everywhere he has not said otherwise.) What is chosen does not leave the room: it stands above
/// the field as an attachment, and the field grows upward under it.
struct MTGalleryPick: View {
    @ObservedObject var recent: RecentMedia
    /// The ceiling of one pick, the platform own and ours alike (the author word 22.09): ten.
    static let limit = 10
    /// The camera's own name among the pictures — the plate's grid calls it by the same one.
    static let cameraId = AttachSheet.cameraId
    var onPick: ([PHAsset]) -> Void       // what was chosen, in the order it was chosen
    var onCamera: () -> Void = {}         // the camera, as the plate own grid has always held it
    var onAllPhotos: () -> Void           // the platform own picker, with its collections
    @Environment(\.dismiss) private var dismiss
    @State private var selected: [String] = []
    /// THE PICTURES BY THEIR NAMES (the critic 22.09): the page reads six hundred of them, and a
    /// walk through the array for every tile the grid builds is six hundred comparisons per tile.
    /// The names are put in a book once, when the library answers, and every tile asks the book.
    @State private var byId: [String: PHAsset] = [:]
    var body: some View {
        // THE CAMERA KEEPS ITS DOOR (22.09): with the «+» plate opened onto the bar, the camera would
        // have lost the only way to it, so it stands as the first tile of the grid — where the plate's
        // own grid has always had it. It takes no place in a pick and no drag ever touches it.
        MTTileGrid(ids: [Self.cameraId] + recent.assets.map(\.localIdentifier),
                   selected: $selected, fixed: [Self.cameraId], limit: Self.limit) { id in
            if id == Self.cameraId {
                MTCameraTile(action: onCamera)
            } else if let a = byId[id] {
                // The circle is OUR gold with its number (the author's word 22.09), as everywhere else.
                SelectableThumb(asset: a, order: selected.firstIndex(of: id),
                                onPreview: { toggle(id) }, onToggle: { toggle(id) })
            }
        } prefetch: { ids in MTAssetImages.preheat(ids.compactMap { byId[$0] }) }
        .overlay {
            // Only a REFUSAL is said in words (the critic 22.09): an empty grid also stands for the
            // moment between the answer and the pictures — and THAT moment is the platform's own
            // spinner now, never a black void (the author's word 22.09).
            if recent.status == .denied || recent.status == .restricted {
                Text("No access to photos").foregroundColor(.gray).font(.subheadline)
            } else if recent.assets.isEmpty {
                ProgressView()
            }
        }
        // THE FOOT IS AN INSET, NOT A LID (the critic 22.09): as an overlay it covered the last row of
        // tiles and nothing could reach them. The platform's own safe-area inset both floats it over
        // the grid — the pictures travel under it, as in his screenshots — and gives the grid that
        // room, so the last picture is reachable.
        .safeAreaInset(edge: .bottom) { foot }
        .background(Color.black.ignoresSafeArea())
        .onAppear { recent.want(600); recent.load(); recent.refresh(); take(recent.assets) }
        .onChange(of: recent.assets) { _, a in take(a) }
    }
    private func take(_ assets: [PHAsset]) {
        byId = Dictionary(assets.map { ($0.localIdentifier, $0) }, uniquingKeysWith: { a, _ in a })
    }
    /// One at a time, up to the ceiling; a second touch takes the picture back out of the pick.
    private func toggle(_ id: String) {
        if let i = selected.firstIndex(of: id) { selected.remove(at: i) }
        else if selected.count < Self.limit { selected.append(id) }
    }
    private var foot: some View {
        HStack(spacing: 10) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold)).foregroundColor(MontanaOctagon.barGlyph)
            }
            .buttonStyle(.montanaOctagon(square: true, bar: true, height: montanaTouchTarget))
            Spacer(minLength: 0)
            if selected.isEmpty {
                // «All photos» is the platform's whole-library page in every state (24.09): under limited
                // access the platform's page for that state wore every allowed picture ticked; this one opens clean.
                Button { onAllPhotos() } label: {
                    Text("All photos").font(.system(size: 16, weight: .medium)).foregroundColor(.white)
                }
                .buttonStyle(.montanaOctagon(bar: true, height: montanaTouchTarget))
            } else {
                Button { hand() } label: {
                    Text("Add \(selected.count) photos").font(.system(size: 16, weight: .semibold)).foregroundColor(.black)
                }
                .buttonStyle(.montanaOctagon(prominent: true, height: montanaTouchTarget))
            }
        }
        .padding(.horizontal, 16).padding(.bottom, 10)
    }
    private func hand() {
        let picked = selected.compactMap { byId[$0] }
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { onPick(picked) }
    }
}

/// A PICTURE HANDED TO THE FIELD (24.09): the library's own, when it names the picture to this app, or
/// the whole-library page's own hand-over of one it will not name (limited access). One road stages
/// both, in the order the finger chose them (stagePicks).
enum MTPick {
    case asset(PHAsset)
    case provider(NSItemProvider)
}

/// THE PLATFORM'S OWN WHOLE-LIBRARY PAGE, IN OUR GOLD (the author's word 22.09: «bring the system one
/// back and make the choosing as on the screen — the tick in our gold, the colour of the mark; there
/// everything works»). A page of our own was tried for this and refused: what the person wants here is
/// the platform's page — its collections, its search, its pinch, its own everything — and from us only
/// the colour and the road home.
///
/// Two things are ours: the tint the page is asked to wear (a picker is a page of another process, and
/// the platform carries the host's tint into it — asked here on the controller and on its view), and
/// the shape of what comes back. Asking the library itself (`photoLibrary: .shared()`) makes the answer
/// carry the library's own NAMES, so the pictures walk the very road our own grid walks — one owner of
/// staging (stagePicks), no second copy of a picture, no second shape of an answer. Under limited access
/// the library names only what the person allowed; every other picture is handed over by the page itself
/// (MTPick.provider), so nothing picked is dropped (the author's word 24.09).
struct MTSystemPhotos: UIViewControllerRepresentable {
    let limit: Int
    var onPick: ([MTPick]) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var c = PHPickerConfiguration(photoLibrary: .shared())
        c.selectionLimit = limit
        c.filter = .any(of: [.images, .videos])
        c.selection = .default          // the tick, as the author's screen shows it
        c.preferredAssetRepresentationMode = .current
        let p = PHPickerViewController(configuration: c)
        p.delegate = context.coordinator
        p.view.tintColor = UIColor.white
        p.overrideUserInterfaceStyle = .dark
        return p
    }
    func updateUIViewController(_ p: PHPickerViewController, context: Context) {
        p.view.tintColor = UIColor.white   // re-asked after the page lays itself out
    }
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: MTSystemPhotos
        init(_ p: MTSystemPhotos) { parent = p }
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            // The order the finger chose them in is the order they come back in. A picture the library
            // names to this app walks as the library's own; one it will not name (limited access, 24.09)
            // is handed over by the page itself, so nothing picked is dropped.
            parent.dismiss()
            guard !results.isEmpty else { return }
            let names = results.compactMap { $0.assetIdentifier }
            let found = PHAsset.fetchAssets(withLocalIdentifiers: names, options: nil)
            var book: [String: PHAsset] = [:]
            found.enumerateObjects { a, _, _ in book[a.localIdentifier] = a }
            let picks: [MTPick] = results.map { r in
                if let n = r.assetIdentifier, let a = book[n] { return .asset(a) }
                return .provider(r.itemProvider)
            }
            MontanaTrace.mark("photos_all", "picked=\(results.count) named=\(book.count)")
            let hand = parent.onPick
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { hand(picks) }
        }
    }
}

// pick a contact from the phone book → return the string "name + phone"
struct ContactPicker: UIViewControllerRepresentable {
    var onPick: (CNContact) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> CNContactPickerViewController {
        let p = CNContactPickerViewController()
        p.delegate = context.coordinator
        return p
    }
    func updateUIViewController(_ c: CNContactPickerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, CNContactPickerDelegate {
        let parent: ContactPicker
        init(_ p: ContactPicker) { parent = p }
        func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
            parent.onPick(contact)
            parent.dismiss()
        }
        func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
            parent.dismiss()
        }
    }
}

// capture a photo/video with the phone camera
struct CameraPicker: UIViewControllerRepresentable {
    var onImage: (UIImage) -> Void
    var onVideo: (URL) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let p = UIImagePickerController()
        p.sourceType = .camera
        p.mediaTypes = ["public.image", "public.movie"]
        p.videoQuality = .typeHigh   // the best the system camera gives; the send road sizes it itself
        p.delegate = context.coordinator
        MontanaScreenAwake.hold("camera")   // the screen stays awake while the camera is up (18.09)
        return p
    }
    func updateUIViewController(_ c: UIImagePickerController, context: Context) {}
    static func dismantleUIViewController(_ c: UIImagePickerController, coordinator: Coordinator) { MontanaScreenAwake.release("camera") }
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ p: CameraPicker) { parent = p }
        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let url = info[.mediaURL] as? URL {
                parent.onVideo(url)
            } else if let img = info[.originalImage] as? UIImage {
                parent.onImage(img)
            }
            parent.dismiss()
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

// full-screen viewer for a video message
// A player with a video layer and a floating window started programmatically. The system
// AVPlayerViewController folds only on its own (when the app goes background), so a custom
// layer lives here: swipe-down must fold immediately, on the gesture.
// Requires the «audio» background mode — already declared in Info.plist.
// The video-viewing keeper. The system player gives the native controls — seek, scrubber,
// speed, subtitles, the fold button — both full screen and in the floating window. A
// hand-rolled «layer + controller» pair took all of that away: a bare layer draws nothing,
// and there was nowhere to return from the window.
// The keeper exists so the player outlives the screen's closing: while the floating window
// runs, the SwiftUI view is long gone, and the video must keep playing.
enum VideoKeeper {
    static var controller: AVPlayerViewController?
    static var player: AVPlayer?
    static var file: String?
    /// The screen asks to expand the viewer back — installs its handler here.
    static var onRestore: ((String) -> Void)?
    /// Whether the floating window is running. The system player does not expose this flag,
    /// so we track it ourselves from delegate events.
    static var inPiP = false
    /// The user tapped «expand», not «close».
    static var restoring = false
    /// The mini window's long-lived delegate — outlives the SwiftUI layer's closing.
    static let delegate = VideoKeeperDelegate()

    static func release() {
        MontanaTelemetry.shared.event("VIDEO release()")
        player?.pause()
        // Unloading the clip: the system player can resume playback by itself after its own
        // transitions (the panel's close button) — an empty player has nothing to resume.
        player?.replaceCurrentItem(with: nil)
        controller?.player?.pause()
        controller?.player?.replaceCurrentItem(with: nil)
        controller = nil; player = nil; file = nil; inPiP = false; restoring = false
    }
}

// The ONE entrance to video viewing. The player shows natively (modally) — close, swipe-down,
// the mini window and «expand» are handled by the system itself; our part is to silence the
// player when the system reports the close.
enum VideoPresenter {
    /// «Share» on the player (the author's word 10.09): the system's «…» menu takes no items on
    /// iOS, so the button stands on the player's own view, top right — the file goes to the
    /// system sheet: save to Photos, send on, anything the sheet offers.
    static func attachShareMenu(_ c: AVPlayerViewController, file: String) {
        let btn = UIButton(type: .system)
        btn.setImage(UIImage(systemName: "square.and.arrow.up", withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold)), for: .normal)
        btn.tintColor = .white
        btn.backgroundColor = UIColor(white: 0, alpha: 0.35)
        btn.layer.cornerRadius = MontanaOctagon.height / 2
        btn.accessibilityLabel = String(localized: "Share", bundle: MTLanguage.bundle)
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.addAction(UIAction { [weak c] _ in
            guard let c else { return }
            let url = MontanaMediaVault.playableURL(file) ?? attachmentURL(file)
            guard FileManager.default.fileExists(atPath: url.path) else { return }   // a file still being laid (a stream) is not shared yet
            MTShare.present([url], from: btn)   // the one door of every modal (MTTop, 25.09)
        }, for: .touchUpInside)
        c.view.addSubview(btn)
        NSLayoutConstraint.activate([
            btn.widthAnchor.constraint(equalToConstant: MontanaOctagon.height),
            btn.heightAnchor.constraint(equalToConstant: MontanaOctagon.height),
            btn.topAnchor.constraint(equalTo: c.view.safeAreaLayoutGuide.topAnchor, constant: 8),
            btn.trailingAnchor.constraint(equalTo: c.view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
        ])
    }
    static func present(remote url: URL) {
        let name = url.lastPathComponent.isEmpty ? "link" : url.lastPathComponent
        present(name) { AVPlayerItem(url: url) }
    }
    static func present(_ file: String) {
        present(file) { AVPlayerItem(url: MontanaMediaVault.playableURL(file) ?? attachmentURL(file)) }
    }
    /// THE SAME ROAD FOR A FILE NOT YET WHOLE (the author's word 25.09: «a tap on a video starts it at once, with a
    /// buffer»): the player reads the file through its loader from the pieces the lane brings — playing from the first
    /// ones, a few seconds buffered ahead, never the whole file. Whole, the file stands under its name and `whole` is told.
    static func present(stream s: MTStreamSource, whole: (() -> Void)? = nil) {
        present(s.name) {
            let item = AVPlayerItem(asset: MTStreams.asset(s, whole: whole))
            item.preferredForwardBufferDuration = 8
            return item
        }
    }
    private static func present(_ file: String, item: () -> AVPlayerItem) {
        MontanaAudioSession.activatePlayback()
        if let f = VideoKeeper.file, f != file { VideoKeeper.release() }
        let c: AVPlayerViewController
        if let kept = VideoKeeper.controller, VideoKeeper.file == file {
            c = kept   // returning from the mini window: the same player, the same second
        } else {
            VideoKeeper.release()
            c = AVPlayerViewController()
            c.player = AVPlayer(playerItem: item())
            c.allowsPictureInPicturePlayback = true
            c.canStartPictureInPictureAutomaticallyFromInline = true
            c.delegate = VideoKeeper.delegate
            attachShareMenu(c, file: file)
            VideoKeeper.controller = c
            VideoKeeper.player = c.player
            VideoKeeper.file = file
        }
        VideoKeeper.onRestore = { f in DispatchQueue.main.async { VideoPresenter.present(f) } }
        guard c.presentingViewController == nil else { c.player?.play(); return }
        MTTop.present(c, kind: "video") { c.player?.play() }
    }

    static func topVC() -> UIViewController? {
        let win = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }.first
        var t = win?.rootViewController
        while let p = t?.presentedViewController { t = p }
        return t
    }
}

// One viewer for faces and pictures: no rise animation and the decode already held, so a tap answers at once.
final class MTPhotoShown: ObservableObject {
    @Published var image: UIImage?
    init(_ image: UIImage?) { self.image = image }
}
private struct MTPhotoLook: View {
    @ObservedObject var shown: MTPhotoShown
    let onClose: () -> Void
    var body: some View { MontanaPhotoViewer(image: shown.image, onClose: onClose) }
}
enum PhotoPresenter {
    private static weak var host: UIViewController?
    /// ONE ROAD FOR A PICTURE AMONG PICTURES (the author's words 05.10.2026 14:04, 15:04 and 18:24 MSK: «photos dropped into the
    /// chat -- paging by a tap at the edge or a swipe aside»; «by constitution 0, in the posts and everywhere one function»; «our
    /// task of the edge taps, by constitution 0»): every tap on a picture -- a chat's, a post's, a correspondent's page -- comes
    /// here with the pictures it stands among, oldest first, and opens OUR album (MontanaPhotoViewer: the system's page view
    /// controller for the swipe, the tap in the outer 15 % turns the page, the native zoom, the pull that closes). The platform's
    /// QuickLook viewer of 2116 drew its pages in another process, where a tap of ours never arrived (T1 18:13, among=48, no turn).
    /// A lone picture, or one not among them, keeps the quick viewer. Every turn is a line of the diary (photo_page).
    static func present(_ file: String, among moments: [MTMoment]) {
        guard 1 < moments.count, moments.contains(where: { m in m.id == file }) else { present(file); return }
        // A post's pictures lie in the media store, a chat's where docImage finds them: a page is read from its moment's own file.
        let urls = Dictionary(moments.map { m in (m.id, m.url) }, uniquingKeysWith: { a, _ in a })
        let files = moments.map { m in m.id }
        Task { @MainActor in
            guard host == nil else {
                MontanaTrace.markFolded("photo_look", "held -- one viewer stands, this tap is not a second one", window: 5); return
            }
            MontanaTrace.mark("photo_look", "album among=\(files.count) at=\(files.firstIndex(of: file) ?? -1)")
            let h = MontanaHost.make(MontanaPhotoViewer(
                image: docImageCached(file), files: files, startFile: file,
                loader: { f in docImageCached(f) ?? urls[f].flatMap { u in UIImage(contentsOfFile: u.path) } },
                onPage: { f in MontanaTrace.mark("photo_page", "at=\(files.firstIndex(of: f) ?? -1) of=\(files.count)") },
                onClose: { if let s = PhotoPresenter.host { MTTop.dismiss(s, animated: false, kind: "photo") } }))
            h.view.backgroundColor = .clear
            h.modalPresentationStyle = .overFullScreen
            host = h
            MTTop.present(h, animated: false, kind: "photo")
        }
    }
    static func present(_ file: String) {
        if mtIsVideoName(file) { VideoPresenter.present(file); return }
        present(now: docImageCached(file)) { await Task.detached(priority: .userInitiated) { docImage(file) }.value }
    }
    /// now shows at once; whole replaces it once decoded.
    static func present(now: UIImage?, whole: @escaping () async -> UIImage?) {
        Task { @MainActor in
            guard host == nil else {   // one viewer; a dropped tap is written down
                MontanaTrace.markFolded("photo_look", "held -- one viewer stands, this tap is not a second one", window: 5); return
            }
            var first = now
            if first == nil { first = await whole() }
            guard let first else { MontanaTrace.mark("photo_look", "nothing to show"); return }
            guard host == nil else { MontanaTrace.markFolded("photo_look", "held -- a viewer rose while this one was decoded", window: 5); return }
            MontanaTrace.mark("photo_look", "open at_once=\(now == nil ? 0 : 1)")
            let shown = rise(first)
            guard now != nil, let sharp = await whole() else { return }
            shown.image = sharp
        }
    }
    /// Only the view holds the host, so a closed viewer is gone at once, however long the sharp picture takes.
    @MainActor private static func rise(_ first: UIImage) -> MTPhotoShown {
        let shown = MTPhotoShown(first)
        let h = MontanaHost.make(MTPhotoLook(shown: shown) {
            if let s = PhotoPresenter.host { MTTop.dismiss(s, animated: false, kind: "photo") }
        })
        h.view.backgroundColor = .clear
        h.modalPresentationStyle = .overFullScreen
        host = h
        MTTop.present(h, animated: false, kind: "photo")
        return shown
    }
}

// The mini-window delegate. Lives in the keeper for the app's whole run, so system events
// arrive even after the SwiftUI viewing layer has long closed.
final class VideoKeeperDelegate: NSObject, AVPlayerViewControllerDelegate {
    // Measurement instead of guessing: every player event is a journal line. Precedent: three
    // builds fixed the close button around an event whose arrival was never once verified.
    func playerViewController(_ c: AVPlayerViewController,
                              willBeginFullScreenPresentationWithAnimationCoordinator coordinator: UIViewControllerTransitionCoordinator) {
        MontanaTelemetry.shared.event("VIDEO willBeginFullScreen")
    }

    // Close the full-screen layer BEFORE the window appears — otherwise a black frame flashes.
    func playerViewControllerWillStartPictureInPicture(_ c: AVPlayerViewController) {
        MontanaTelemetry.shared.event("VIDEO PiP start")
        VideoKeeper.inPiP = true
    }

    // The mini window is up — close the empty modal screen beneath it (that WAS the «black
    // backdrop»). The player lives in the keeper, the mini window keeps playing; «expand»
    // shows the same screen anew. The close button is untouched: it has its own road
    // (willEndFullScreen), and release is not called here.
    func playerViewControllerDidStartPictureInPicture(_ c: AVPlayerViewController) {
        MontanaTelemetry.shared.event("VIDEO PiP started — removing the modal backdrop")
        MTTop.dismiss(c, kind: "video-pip")
    }

    // «Expand» on the mini window: the screen reopens with the same player.
    func playerViewController(_ c: AVPlayerViewController,
                              restoreUserInterfaceForPictureInPictureStopWithCompletionHandler h: @escaping (Bool) -> Void) {
        VideoKeeper.restoring = true
        MontanaTelemetry.shared.event("VIDEO PiP expand")
        if let f = VideoKeeper.file, let restore = VideoKeeper.onRestore {
            restore(f); h(true)
        } else {
            VideoKeeper.restoring = false; h(false)
        }
    }

    // The player's own SYSTEM close button (control panel). The event used to be ignored:
    // the system hid the video while the player kept sounding «somewhere». The button cannot
    // be removed — it is part of the native panel; so it becomes a full close.
    // Native player close/swipe: the system closes by itself, we silence on its transition's
    // end. Going to the mini window is not a close.
    func playerViewController(_ c: AVPlayerViewController,
                              willEndFullScreenPresentationWithAnimationCoordinator coordinator: UIViewControllerTransitionCoordinator) {
        MontanaTelemetry.shared.event("VIDEO willEndFullScreen (close/swipe) inPiP=\(VideoKeeper.inPiP)")
        coordinator.animate(alongsideTransition: nil) { _ in
            MontanaTelemetry.shared.event("VIDEO close transition finished")
            if !VideoKeeper.inPiP { VideoKeeper.release() }
        }
    }

    // The mini-window close button is a full close: the player goes dark, the sound stops.
    func playerViewControllerDidStopPictureInPicture(_ c: AVPlayerViewController) {
        MontanaTelemetry.shared.event("VIDEO PiP stop restoring=\(VideoKeeper.restoring)")
        VideoKeeper.inPiP = false
        if !VideoKeeper.restoring {
            VideoKeeper.release()
            return
        }
        VideoKeeper.restoring = false
    }
}

extension Notification.Name {
    /// The chat's last voice ended while the phone was at the ear: the reply is recorded there.
    static let montanaVoiceEndedAtEar = Notification.Name("montanaVoiceEndedAtEar")
}

/// THE EAR TONE (the author's word 14.09): a short two-note chime played THROUGH the audio
/// session, so it follows the session's route — the receiver at the ear — and ignores the
/// silent switch, unlike a system sound. Built in memory, no file.
enum MontanaEarTone {
    private static var player: AVAudioPlayer?
    static func play() {
        let rate = 44_100.0
        // ONE DULL LOW NOTE (the author's word 16.09: as a dictaphone marks the start of a tape —
        // duller and quieter than the three bright notes that stood here): 320 Hz, a seventh of a
        // second, a soft rise and a long fall, an eighth of the amplitude.
        let notes: [(hz: Double, s: Double)] = [(320, 0.14)]
        var samples: [Int16] = []
        for n in notes {
            let count = Int(rate * n.s)
            for i in 0..<count {
                let t = Double(i) / rate
                let env = min(1, Double(i) / 900, Double(count - i) / 3000)   // no clicks, no edge at all
                samples.append(Int16(sin(2 * .pi * n.hz * t) * 0.12 * env * 32767))
            }
        }
        var data = Data()
        func le32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
        func le16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
        let bytes = UInt32(samples.count * 2)
        data.append(contentsOf: Array("RIFF".utf8)); le32(36 + bytes); data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8)); le32(16); le16(1); le16(1); le32(UInt32(rate)); le32(UInt32(rate) * 2); le16(2); le16(16)
        data.append(contentsOf: Array("data".utf8)); le32(bytes)
        samples.withUnsafeBytes { data.append(contentsOf: $0) }
        player = try? AVAudioPlayer(data: data)
        player?.volume = 1
        let ok = player?.play() ?? false
        MontanaTrace.mark("voice_ear_reply", "tone played=\(ok ? 1 : 0)")
    }
}
