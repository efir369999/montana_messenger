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
                        thermal: ProcessInfo.processInfo.thermalState)
    }
    /// THE HEAT IS MEASURED, NOT FELT (10.10.2026, the author's word: «freezes and overheating»): T1's diary of three and a half
    /// hours named the phone's thermal state only inside two call summaries, so the minutes it grew hot could not be laid beside
    /// what the app was doing in them. The state at launch and every change of it is one line in the trace and the telemetry,
    /// Low Power Mode beside it; a state that did not change writes nothing (markChanged).
    static func witnessHeat() {
        let say = {
            let p = ProcessInfo.processInfo
            MontanaTrace.markChanged("thermal", "state=\(thermalWord(p.thermalState)) lowpower=\(p.isLowPowerModeEnabled ? 1 : 0)", tele: true)
        }
        say()
        NotificationCenter.default.addObserver(forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: nil) { _ in say() }
        NotificationCenter.default.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: nil) { _ in say() }
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
}
