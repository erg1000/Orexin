//
//  SleepAssertionMonitor.swift
//  Orexin
//

import AppKit
import IOKit.pwr_mgt
import notify
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
    /// When the oldest of this process's assertions was created.
    let since: Date

    var id: pid_t { pid }

    /// Stable identity across process restarts, used for the ignore list and history.
    var key: String { bundleIdentifier ?? name }

    var isOwnProcess: Bool { pid == ProcessInfo.processInfo.processIdentifier }

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

    /// Called with the new blockers after every refresh.
    var onUpdate: (([SleepBlocker]) -> Void)?

    private var timer: Timer?
    private var notifyToken = NOTIFY_TOKEN_INVALID
    private var refreshScheduled = false

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

    /// Assertions that macOS always holds or that only last while the Mac is in use.
    private static let ignoredAssertionNames: Set<String> = [
        "Powerd - Prevent sleep while display is on",
        // sharingd's short-lived Handoff advertising.
        "Handoff",
    ]

    /// Processes whose assertions only last while the Mac is in use, so they never block idle sleep.
    private static let ignoredProcessNames: Set<String> = [
        // Handoff: briefly advertises the current activity to nearby devices.
        "useractivityd",
    ]

    private static let anyChangeNotification = "com.apple.system.powermanagement.assertions.anychange"

    /// Refreshes whenever power assertions change, plus periodically so that durations and
    /// long-block alerts stay current. If change notifications aren't available, polls more often.
    init() {
        refresh()

        let notificationsEnabled = Self.enableAnyChangeNotifications()
        if notificationsEnabled {
            notify_register_dispatch(Self.anyChangeNotification, &notifyToken, .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.scheduleRefresh() }
            }
        }

        let interval: TimeInterval = notificationsEnabled ? 30 : 5
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        timer?.tolerance = interval / 5
    }

    /// powerd only posts the "any assertion changed" notification to clients that asked for it
    /// through `IOPMAssertionNotify`, which is private API in IOKit, so it's looked up at runtime.
    private static func enableAnyChangeNotifications() -> Bool {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "IOPMAssertionNotify") else {
            return false
        }
        typealias AssertionNotify = @convention(c) (UnsafePointer<CChar>, Int32) -> kern_return_t
        let register: Int32 = 1 // kIOPMNotifyRegister
        return unsafeBitCast(symbol, to: AssertionNotify.self)(anyChangeNotification, register) == kIOReturnSuccess
    }

    func refresh() {
        let current = Self.readBlockers()
        // Avoid redrawing the menu bar when nothing changed; assertion notifications are frequent.
        if current != blockers { blockers = current }
        onUpdate?(blockers)
    }

    /// Assertions change constantly while the Mac is in use (every input event updates one),
    /// so coalesce notifications into at most one refresh per second.
    private func scheduleRefresh() {
        guard !refreshScheduled else { return }
        refreshScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.refreshScheduled = false
            self?.refresh()
        }
    }

    private static func readBlockers() -> [SleepBlocker] {
        var unmanaged: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&unmanaged) == kIOReturnSuccess,
              let byProcess = unmanaged?.takeRetainedValue() as? [NSNumber: [[String: Any]]]
        else { return [] }

        let ownPID = ProcessInfo.processInfo.processIdentifier

        // Group assertions by the app they are really for. Daemons such as coreaudiod
        // create assertions on behalf of other processes, and those processes are often
        // helpers (browser renderers, WebKit services), so attribute them to their app.
        var reasonsByPID: [pid_t: [String]] = [:]
        var kindByPID: [pid_t: SleepBlocker.Kind] = [:]
        var fallbackNames: [pid_t: String] = [:]
        var sinceByPID: [pid_t: Date] = [:]

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
                if let processName = assertion["Process Name"] as? String,
                   ignoredProcessNames.contains(processName) { continue }
                // runningboardd grants apps a few seconds to finish work when they go
                // into the background. These come and go constantly, so skip them.
                if name.contains("Shared Background Assertion") { continue }

                let onBehalfPID = (assertion["AssertionOnBehalfOfPID"] as? NSNumber)?.int32Value
                let pid = owningAppPID(for: onBehalfPID ?? ownerPID.int32Value)

                reasonsByPID[pid, default: []].append(readableReason(for: assertion, name: name))
                // Display assertions are the "stronger" of the two, keep them if present.
                if kindByPID[pid] != .display { kindByPID[pid] = kind }
                let start = assertion["AssertStartWhen"] as? Date ?? .now
                sinceByPID[pid] = min(sinceByPID[pid] ?? start, start)
                // "Process Name" is the assertion owner's name, so it only applies to the owner.
                if onBehalfPID == nil, fallbackNames[pid] == nil,
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
                // Count our own "Keep Mac Awake" assertion as an app so it shows up and turns the dot red.
                isApp: app?.activationPolicy == .regular || pid == ownPID,
                kind: kindByPID[pid] ?? .system,
                reasons: Array(Set(reasons)).sorted(),
                since: sinceByPID[pid] ?? .now
            )
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Turns coreaudiod's technical assertion names into something readable.
    private static func readableReason(for assertion: [String: Any], name: String) -> String {
        let resources = assertion["ResourcesUsed"] as? [String] ?? []
        if resources.contains("audio-out") { return "Playing audio" }
        if resources.contains("audio-in") { return "Recording audio" }
        return name
    }

    /// Returns the PID of the app a process belongs to, or the process itself if it isn't part of an app.
    private static func owningAppPID(for pid: pid_t) -> pid_t {
        if NSRunningApplication(processIdentifier: pid)?.activationPolicy == .regular {
            return pid
        }
        guard let path = executablePath(for: pid) else { return pid }

        // Helpers inside an app bundle, e.g. "Google Chrome.app/…/Google Chrome Helper.app/…".
        if let range = path.range(of: ".app/") {
            let bundleURL = URL(fileURLWithPath: String(path[..<range.lowerBound]) + ".app")
                .standardizedFileURL
            if let app = NSWorkspace.shared.runningApplications.first(where: {
                $0.activationPolicy == .regular && $0.bundleURL?.standardizedFileURL == bundleURL
            }) {
                return app.processIdentifier
            }
        }

        // XPC services launched for an app, e.g. Safari's "com.apple.WebKit.GPU.xpc".
        if path.contains(".xpc/"), let responsible = responsiblePID(for: pid), responsible != pid,
           NSRunningApplication(processIdentifier: responsible)?.activationPolicy == .regular {
            return responsible
        }

        return pid
    }

    private static func executablePath(for pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return String(cString: buffer)
    }

    /// The process macOS holds responsible for `pid` (e.g. the app that launched an XPC service).
    /// This is private API in libsystem, so it's looked up at runtime and may be unavailable.
    private static let responsibilityFunction: (@convention(c) (pid_t) -> pid_t)? = {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2),
                                 "responsibility_get_pid_responsible_for_pid")
        else { return nil }
        return unsafeBitCast(symbol, to: (@convention(c) (pid_t) -> pid_t).self)
    }()

    private static func responsiblePID(for pid: pid_t) -> pid_t? {
        guard let function = responsibilityFunction else { return nil }
        let responsible = function(pid)
        return responsible > 0 ? responsible : nil
    }

    private static func processName(for pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        guard proc_name(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return String(cString: buffer)
    }
}
