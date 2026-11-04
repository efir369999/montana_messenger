//
//  MontanaPower.swift
//  Montana — a Montana messenger
//
//  THE POWER FACTS (the author's word 10.09: a call must never eat the battery). One reading of
//  the battery, the charger, Low Power Mode and the thermal state — the call's ladder, the call's
//  journal and its summary read it here and nowhere else.
//

import UIKit

enum MontanaPower {
    struct Snapshot {
        let level: Int          // 0…100, -1 when the system does not say
        let charging: Bool
        let lowPower: Bool
        let thermal: ProcessInfo.ThermalState
        /// The run's own processor time at the reading, in microseconds (runMicros): two readings give a call's share of one
        /// core -- the heat the app itself made, beside the heat the phone reports.
        let cpuMicros: UInt64
        var word: String {
            "batt=\(level) chg=\(charging ? 1 : 0) lowpower=\(lowPower ? 1 : 0) thermal=\(MontanaPower.thermalWord(thermal))"
        }
        /// THE POWER FLOOR of the video ladder: the step the picture may not rise above while the
        /// phone is under power pressure. 0 — none. 2 (700 kbps, half resolution, 15 fps) under
        /// Low Power Mode, a serious thermal state, or a battery at 15 % or less off the charger.
        /// 4 (250 kbps) under a critical thermal state — the phone is about to throttle itself.
        var ladderFloor: Int {
            if thermal == .critical { return 4 }
            if lowPower || thermal == .serious || (!charging && level >= 0 && level <= 15) { return 2 }
            return 0
        }
    }
    /// Main thread only: the battery facts are the device's, and the device speaks on main.
    static func snapshot() -> Snapshot {
        let d = UIDevice.current
        if !d.isBatteryMonitoringEnabled { d.isBatteryMonitoringEnabled = true }
        let lvl = d.batteryLevel < 0 ? -1 : Int((d.batteryLevel * 100).rounded())
        let chg = d.batteryState == .charging || d.batteryState == .full
        return Snapshot(level: lvl, charging: chg,
                        lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled,
                        thermal: ProcessInfo.processInfo.thermalState, cpuMicros: runMicros())
    }
    /// THE HEAT IS MEASURED, NOT FELT (10.10.2026, the author's word: «freezes and overheating»): T1's diary of three and a half
    /// hours named the phone's thermal state only inside two call summaries, so the minutes it grew hot could not be laid beside
    /// what the app was doing in them. The state at launch and every change of it is one line in the trace and the telemetry,
    /// Low Power Mode beside it; a state that did not change writes nothing (markChanged).
    /// THE LINE CARRIES WHAT HEATS A PHONE BESIDE US (16.10.2026, No.70: a tester's iPhone 16 stood «serious» at 06:58 after
    /// 107 minutes the app slept, and the line could not say whether the phone stood on its charger). Beside the state: the
    /// battery and the charger, whether the app faced the person, the call in hand, and the share of one core the run itself
    /// took since its last reading (readLoad). The system speaks of the heat on a thread of its own; the battery and the
    /// scene are the main thread's, and the line is written there.
    static func witnessHeat() {
        rememberMain()
        let say = {
            let p = ProcessInfo.processInfo
            let s = snapshot()
            keepFloor(s)
            let scene = UIApplication.shared.applicationState == .background ? "bg" : "fg"
            let load = readLoad("thermal", tele: true)
            MontanaTrace.markChanged("thermal", "state=\(thermalWord(p.thermalState)) lowpower=\(p.isLowPowerModeEnabled ? 1 : 0) "
                + "batt=\(s.level) chg=\(s.charging ? 1 : 0) scene=\(scene) call=\(MontanaCall.stateSnapshot) cpu_pct=\(load)", tele: true)
        }
        say()
        NotificationCenter.default.addObserver(forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: .main) { _ in say() }
        NotificationCenter.default.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { _ in say() }
        // The battery and the charger move the floor too (fifteen percent off the charger), without a line of their own.
        for name in [UIDevice.batteryLevelDidChangeNotification, UIDevice.batteryStateDidChangeNotification] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in keepFloor(snapshot()) }
        }
    }
    /// ONE OWNER OF THE HEAT'S ANSWER (16.10.2026, No.70, the critic's deep closure): the video ladder read the power facts on
    /// its own tick and stepped down under heat. The floor is reckoned by the one rule (Snapshot.ladderFloor)
    /// whenever the heat, Low Power Mode, the battery or the charger changes, and every heavy work reads it here, on any thread:
    /// 0 -- free, 2 -- under pressure, 4 -- critical.
    private static let floorLock = NSLock()
    private static var floor = 0
    static var floorNow: Int { floorLock.lock(); defer { floorLock.unlock() }; return floor }
    private static func keepFloor(_ s: Snapshot) { floorLock.lock(); floor = s.ladderFloor; floorLock.unlock() }
    /// A WORK OF GIGABYTES WAITS FOR THE CHARGER (the author's word 16391, 04.11.2026 17:07 UTC: «do not allow such a thing at the
    /// root and fix it urgently»). T1 on 2358, 16:17-17:02Z: the copy kept by the people one writes to (MTKeeping) laid some 5 800
    /// pieces of 512 KB on the nodes, ~850 a minute, each with its mirror -- on the battery, the processor at 100-170 %, the phone
    /// serious, the tunnel killed for memory 17 times. Such a work runs only on the charger, outside Low Power Mode, at a heat no
    /// higher than fair and on a path that is not metered, as the system's own copy waits for them. Nil -- go; else why it waits.
    /// Main thread (the battery is the device's).
    static func bulkHeld() -> String? {
        let s = snapshot()
        if !s.charging { return "battery" }
        if s.lowPower { return "lowpower" }
        if ProcessInfo.ThermalState.fair.rawValue < s.thermal.rawValue { return "thermal=" + thermalWord(s.thermal) }
        if MontanaNetWitness.metered { return "metered" }
        return nil
    }
    static func thermalWord(_ t: ProcessInfo.ThermalState) -> String {
        switch t {
        case .nominal: return "nominal"
        case .fair: return "fair"
        case .serious: return "serious"
        case .critical: return "critical"
        @unknown default: return "?"
        }
    }

    // ── THE RUN'S OWN LOAD (16.10.2026, No.70; the author's word: «a tester's phone heats -- check what affects it, close the
    // holes in the metrics»). The system says how hot the phone is and, once a day, how many seconds of processor and graphics
    // the app took (METRICKIT DAY); nothing said WHEN the run burned them, nor on WHICH of its threads. Phones that ran mostly
    // in the background burned up to 1.7 cores for every second they ran, and no line could name the thread. For every minute
    // the run is awake the kernel's own count of each thread's processor time is read (task_threads and thread_info on the
    // process's own threads: a count of time and the name its code gave the thread, never a byte of what it carries): the
    // share of one core the run took, the main thread's share, the heaviest kinds of thread. A line in the trace each awake
    // minute; the day-long journal keeps it every five, at every scene change and at every thermal change.
    private static let loadLock = NSLock()
    private static var mainThread: UInt64 = 0
    private static var seen: [UInt64: UInt64] = [:]    // thread id: its processor microseconds at the last reading
    private static var seenRun: UInt64 = 0             // the run's processor microseconds at the last reading
    private static var awake = 0                        // awake seconds since the last reading (the watchdog's beats)
    private static var beats = 0
    private static var lastPct = "-"

    private static func rememberMain() {
        var id: UInt64 = 0
        pthread_threadid_np(nil, &id)
        loadLock.lock(); mainThread = id; loadLock.unlock()
    }
    /// The run's processor time over every thread it ever had, in microseconds (the kernel's rusage of this process).
    static func runMicros() -> UInt64 {
        var u = rusage()
        guard getrusage(RUSAGE_SELF, &u) == 0 else { return 0 }
        let user = UInt64(u.ru_utime.tv_sec) * 1_000_000 + UInt64(u.ru_utime.tv_usec)
        let system = UInt64(u.ru_stime.tv_sec) * 1_000_000 + UInt64(u.ru_stime.tv_usec)
        return user + system
    }
    /// One beat of the watchdog, once a second while the run is awake: sixty awake beats are one reading.
    static func beat() {
        loadLock.lock(); awake += 1; beats += 1; let due = 60 <= awake; let five = beats % 300 == 0; loadLock.unlock()
        if due { readLoad(five ? "five" : "minute", tele: five) }
    }
    /// Each live thread of the run: its id, the name its code gave it (empty for a pool's worker), its processor microseconds.
    private static func threads() -> [(id: UInt64, name: String, micros: UInt64)] {
        var list: thread_act_array_t?
        var count: mach_msg_type_number_t = 0
        guard task_threads(mach_task_self_, &list, &count) == KERN_SUCCESS, let list else { return [] }
        defer {
            // The rights and the array are the caller's to give back (task_threads): one right per thread, one region.
            for i in 0..<Int(count) { mach_port_deallocate(mach_task_self_, list[i]) }
            vm_deallocate(mach_task_self_, .init(UInt(bitPattern: list)), vm_size_t(Int(count) * MemoryLayout<thread_t>.stride))
        }
        var out: [(id: UInt64, name: String, micros: UInt64)] = []
        for i in 0..<Int(count) {
            var ident = thread_identifier_info_data_t()
            var n = mach_msg_type_number_t(MemoryLayout<thread_identifier_info_data_t>.size / MemoryLayout<natural_t>.size)
            let named = withUnsafeMutablePointer(to: &ident) {
                $0.withMemoryRebound(to: integer_t.self, capacity: Int(n)) { thread_info(list[i], thread_flavor_t(THREAD_IDENTIFIER_INFO), $0, &n) }
            }
            var info = thread_extended_info_data_t()
            var m = mach_msg_type_number_t(MemoryLayout<thread_extended_info_data_t>.size / MemoryLayout<natural_t>.size)
            let timed = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: integer_t.self, capacity: Int(m)) { thread_info(list[i], thread_flavor_t(THREAD_EXTENDED_INFO), $0, &m) }
            }
            guard named == KERN_SUCCESS, timed == KERN_SUCCESS else { continue }
            let name = withUnsafeBytes(of: info.pth_name) { raw in String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self) }
            out.append((ident.thread_id, name, (info.pth_user_time + info.pth_system_time) / 1000))
        }
        return out
    }
    /// A thread's kind: its name without the instance the engine adds (an address, a number); a worker of a pool has none.
    private static func kind(_ name: String) -> String {
        let cut = name.components(separatedBy: " 0x")[0]
        let word = cut.trimmingCharacters(in: CharacterSet.decimalDigits.union(.whitespaces).union(CharacterSet(charactersIn: ".-_#")))
        let one = word.replacingOccurrences(of: " ", with: "_")
        return one.isEmpty ? "pool" : String(one.prefix(28))
    }
    /// A reading since the last one: the share of one core the run took over the awake seconds between them, the main
    /// thread's share and the four heaviest kinds of thread. The first reading of a run is the baseline and writes nothing.
    /// Returns the share, for the thermal line.
    @discardableResult
    static func readLoad(_ why: String, tele: Bool = false) -> String {
        let now = threads()
        let run = runMicros()
        loadLock.lock()
        let first = seenRun == 0
        let span = UInt64(max(awake, 1))
        let spent = seenRun <= run ? run - seenRun : 0
        var byKind: [String: UInt64] = [:]
        var main: UInt64 = 0
        var next: [UInt64: UInt64] = [:]
        for t in now {
            let before = seen[t.id] ?? 0
            let d = before <= t.micros ? t.micros - before : 0
            if t.id == mainThread { main += d } else { byKind[kind(t.name), default: 0] += d }
            next[t.id] = t.micros
        }
        // A thread that ended inside the window took its time with it: the run's count keeps it, no live thread names it.
        let live = byKind.values.reduce(main, +)
        let gone = live <= spent ? spent - live : 0
        seen = next; seenRun = run; awake = 0
        let pct = String(spent / span / 10_000)
        if !first { lastPct = pct }
        let shown = lastPct
        loadLock.unlock()
        guard !first else { return shown }
        let top = byKind.sorted { $0.value > $1.value }.prefix(4)
            .map { "\($0.key):\($0.value / span / 10_000)" }.joined(separator: ",")
        let line = "awake_s=\(span) cpu_pct=\(pct) main_pct=\(main / span / 10_000) gone_pct=\(gone / span / 10_000) threads=\(now.count) "
            + "top=\(top.isEmpty ? "-" : top) why=\(why)"
        MontanaTrace.mark("load", line)
        if tele { MontanaLog.event("LOAD " + line) }
        return shown
    }
}
