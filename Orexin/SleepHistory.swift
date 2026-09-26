//
//  SleepHistory.swift
//  Orexin
//

import AppKit
import Observation
import OSLog

/// Something that happened: a period where a process kept the Mac awake, or the Mac sleeping/waking.
struct HistoryEntry: Codable, Identifiable, Hashable {
    enum Kind: String, Codable {
        case blocked, sleep, wake
    }

    var id = UUID()
    let kind: Kind
    let start: Date
    /// When a `.blocked` period ended; `nil` while it's ongoing.
    var end: Date?
    var name: String?
    var key: String?
    var reasons: [String] = []
    var isApp = false

    var duration: TimeInterval { (end ?? .now).timeIntervalSince(start) }
}

/// Records which processes kept the Mac awake and when it slept and woke, persisted across launches.
@MainActor
@Observable
final class SleepHistory {
    /// Finished entries, oldest first.
    private(set) var entries: [HistoryEntry] = []
    /// Blocking periods that are still going on, by blocker key.
    private(set) var ongoing: [String: HistoryEntry] = [:]

    /// Short blocks (e.g. Bluetooth bursts) are noise, so only keep ones at least this long.
    private static let minimumDuration: TimeInterval = 60
    private static let retention: TimeInterval = 14 * 24 * 60 * 60

    private var isAsleep = false
    private var lastWake = Date.distantPast
    private var observers: [NSObjectProtocol] = []

    private let fileURL: URL = {
        let directory = URL.applicationSupportDirectory.appending(path: "Orexin", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appending(path: "history.json")
    }()

    init() {
        load()

        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.willSleep() }
        })
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.didWake() }
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.finishAll(at: .now) }
        })
    }

    /// Updates ongoing blocking periods from the current set of blockers.
    func record(_ blockers: [SleepBlocker]) {
        guard !isAsleep else { return }

        let current = Dictionary(blockers.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })

        for (key, blocker) in current {
            if var entry = ongoing[key] {
                entry.reasons = Array(Set(entry.reasons).union(blocker.reasons)).sorted()
                ongoing[key] = entry
            } else {
                ongoing[key] = HistoryEntry(
                    kind: .blocked,
                    // An assertion that survived a sleep only counts from the wake.
                    start: max(blocker.since, lastWake),
                    name: blocker.name,
                    key: key,
                    reasons: blocker.reasons,
                    isApp: blocker.isApp
                )
            }
        }

        let finished = ongoing.keys.filter { current[$0] == nil }
        guard !finished.isEmpty else { return }
        for key in finished { finish(key, at: .now) }
        save()
    }

    func clear() {
        entries.removeAll()
        save()
    }

    private func willSleep() {
        finishAll(at: .now)
        entries.append(HistoryEntry(kind: .sleep, start: .now))
        isAsleep = true
        save()
    }

    private func didWake() {
        entries.append(HistoryEntry(kind: .wake, start: .now))
        isAsleep = false
        lastWake = .now
        save()
    }

    private func finishAll(at date: Date) {
        for key in Array(ongoing.keys) { finish(key, at: date) }
        save()
    }

    private func finish(_ key: String, at date: Date) {
        guard var entry = ongoing.removeValue(forKey: key) else { return }
        entry.end = date
        if entry.duration >= Self.minimumDuration {
            entries.append(entry)
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        do {
            entries = try JSONDecoder().decode([HistoryEntry].self, from: data)
        } catch {
            Logger().error("Failed to read sleep history: \(error.localizedDescription)")
        }
    }

    private func save() {
        let cutoff = Date.now.addingTimeInterval(-Self.retention)
        entries.removeAll { $0.start < cutoff }
        entries.sort { $0.start < $1.start }
        do {
            try JSONEncoder().encode(entries).write(to: fileURL, options: .atomic)
        } catch {
            Logger().error("Failed to save sleep history: \(error.localizedDescription)")
        }
    }
}
