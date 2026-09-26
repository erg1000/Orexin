//
//  AppModel.swift
//  Orexin
//

import AppKit
import Observation

/// What the menu bar dot shows.
enum SleepStatus {
    /// Nothing relevant is preventing sleep (green).
    case clear
    /// Only system processes are preventing sleep (orange).
    case blockedBySystem
    /// At least one app is preventing sleep (red).
    case blockedByApp
}

/// Ties the monitor, history, alerts and user settings together.
@MainActor
@Observable
final class AppModel {
    let monitor = SleepAssertionMonitor()
    let keepAwake = KeepAwake()
    let launchAtLogin = LaunchAtLogin()
    let history = SleepHistory()
    @ObservationIgnored private let notifier = LongBlockNotifier()
    @ObservationIgnored private let defaults = UserDefaults.standard

    var includeSystemProcesses: Bool {
        didSet { defaults.set(includeSystemProcesses, forKey: "includeSystemProcesses") }
    }

    /// Minutes after which a notification is posted about a blocker; 0 turns alerts off.
    var alertMinutes: Int {
        didSet {
            defaults.set(alertMinutes, forKey: "alertMinutes")
            if alertMinutes > 0 { notifier.requestAuthorization() }
        }
    }

    /// Keys (bundle ID or process name) of blockers the user chose to ignore.
    private(set) var ignoredKeys: Set<String> {
        didSet { defaults.set(Array(ignoredKeys), forKey: "ignoredKeys") }
    }

    init() {
        includeSystemProcesses = defaults.bool(forKey: "includeSystemProcesses")
        alertMinutes = defaults.object(forKey: "alertMinutes") as? Int ?? 30
        ignoredKeys = Set(defaults.stringArray(forKey: "ignoredKeys") ?? [])

        if alertMinutes > 0 { notifier.requestAuthorization() }
        monitor.onUpdate = { [weak self] blockers in self?.handleUpdate(blockers) }
        monitor.refresh()
    }

    // MARK: Blockers

    var appBlockers: [SleepBlocker] { monitor.appBlockers.filter { !isIgnored($0) } }
    var systemBlockers: [SleepBlocker] { monitor.systemBlockers.filter { !isIgnored($0) } }
    var ignoredBlockers: [SleepBlocker] { monitor.blockers.filter(isIgnored) }

    var status: SleepStatus {
        if !appBlockers.isEmpty { return .blockedByApp }
        if includeSystemProcesses, !systemBlockers.isEmpty { return .blockedBySystem }
        return .clear
    }

    func isIgnored(_ blocker: SleepBlocker) -> Bool {
        ignoredKeys.contains(blocker.key)
    }

    func ignore(_ blocker: SleepBlocker) {
        ignoredKeys.insert(blocker.key)
    }

    func stopIgnoring(_ blocker: SleepBlocker) {
        ignoredKeys.remove(blocker.key)
    }

    private func handleUpdate(_ blockers: [SleepBlocker]) {
        history.record(blockers)

        guard alertMinutes > 0 else { return }
        // Alert about what the dot counts, but not about our own Keep Mac Awake.
        let relevant = (includeSystemProcesses ? appBlockers + systemBlockers : appBlockers)
            .filter { !$0.isOwnProcess }
        notifier.check(relevant, threshold: TimeInterval(alertMinutes * 60))
    }
}
