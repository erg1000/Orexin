//
//  SleepAssertionMonitor.swift
//  SleepBlocker
//

import AppKit
import IOKit.pwr_mgt
import Observation

/// A process holding one or more power assertions that keep the Mac awake.
struct SleepBlocker: Identifiable, Hashable {
    enum Kind: Hashable {
        /// Prevents the system from idle sleeping.
        case system
        /// Prevents the display from sleeping (which also keeps the system awake).
        case display
    }

    let pid: pid_t
    let name: String
    let bundleIdentifier: String?
    let isApp: Bool
    let kind: Kind
    let reasons: [String]

    var id: pid_t { pid }

    var icon: NSImage? {
        NSRunningApplication(processIdentifier: pid)?.icon
    }
}

@MainActor
@Observable
final class SleepAssertionMonitor {
    private(set) var blockers: [SleepBlocker] = []

    /// Blockers that belong to regular (user-facing) apps.
    var appBlockers: [SleepBlocker] { blockers.filter(\.isApp) }
    /// Blockers that are background daemons / system processes.
    var systemBlockers: [SleepBlocker] { blockers.filter { !$0.isApp } }

    private var timer: Timer?

    /// Assertion types that prevent idle system sleep.
    private static let systemSleepTypes: Set<String> = [
        "PreventUserIdleSystemSleep",
        "PreventSystemSleep",
        "NoIdleSleepAssertion",
    ]

    /// Assertion types that prevent idle display sleep.
    private static let displaySleepTypes: Set<String> = [
        "PreventUserIdleDisplaySleep",
        "NoDisplaySleepAssertion",
    ]

    /// Assertions that macOS always holds and that are not interesting to the user.
    private static let ignoredAssertionNames: Set<String> = [
        "Powerd - Prevent sleep while display is on",
    ]

    init(interval: TimeInterval = 5) {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func refresh() {
        blockers = Self.readBlockers()
    }

    private static func readBlockers() -> [SleepBlocker] {
        var unmanaged: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&unmanaged) == kIOReturnSuccess,
              let byProcess = unmanaged?.takeRetainedValue() as? [NSNumber: [[String: Any]]]
        else { return [] }

        let ownPID = ProcessInfo.processInfo.processIdentifier

        // Group assertions by the process they are really for. Daemons such as
        // runningboardd create assertions on behalf of apps, so attribute those
        // to the original app.
        var reasonsByPID: [pid_t: [String]] = [:]
        var kindByPID: [pid_t: SleepBlocker.Kind] = [:]
        var fallbackNames: [pid_t: String] = [:]

        for (ownerPID, assertions) in byProcess {
            for assertion in assertions {
                guard let type = assertion[kIOPMAssertionTypeKey] as? String else { continue }

                let kind: SleepBlocker.Kind
                if systemSleepTypes.contains(type) {
                    kind = .system
                } else if displaySleepTypes.contains(type) {
                    kind = .display
                } else {
                    continue
                }

                let name = assertion[kIOPMAssertionNameKey] as? String ?? type
                if ignoredAssertionNames.contains(name) { continue }
                // runningboardd grants apps a few seconds to finish work when they go
                // into the background. These come and go constantly, so skip them.
                if name.contains("Shared Background Assertion") { continue }

                let pid = (assertion["AssertionOnBehalfOfPID"] as? NSNumber)?.int32Value
                    ?? ownerPID.int32Value
                if pid == ownPID { continue }

                reasonsByPID[pid, default: []].append(name)
                // Display assertions are the "stronger" of the two, keep them if present.
                if kindByPID[pid] != .display { kindByPID[pid] = kind }
                if fallbackNames[pid] == nil,
                   let processName = assertion["Process Name"] as? String {
                    fallbackNames[pid] = processName
                }
            }
        }

        return reasonsByPID.map { pid, reasons in
            let app = NSRunningApplication(processIdentifier: pid)
            let name = app?.localizedName
                ?? fallbackNames[pid]
                ?? processName(for: pid)
                ?? "PID \(pid)"
            return SleepBlocker(
                pid: pid,
                name: name,
                bundleIdentifier: app?.bundleIdentifier,
                isApp: app?.activationPolicy == .regular,
                kind: kindByPID[pid] ?? .system,
                reasons: Array(Set(reasons)).sorted()
            )
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private static func processName(for pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        guard proc_name(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return String(cString: buffer)
    }
}
