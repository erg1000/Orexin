//
//  LongBlockNotifier.swift
//  Orexin
//

import Foundation
import OSLog
import UserNotifications

/// Posts a notification when something has kept the Mac awake for longer than a threshold.
@MainActor
final class LongBlockNotifier: NSObject, UNUserNotificationCenterDelegate {
    /// Blocking periods already notified about, so each one only notifies once.
    private var notified: Set<String> = []

    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    func requestAuthorization() {
        Task {
            do {
                _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
            } catch {
                Logger().error("Notification authorization failed: \(error.localizedDescription)")
            }
        }
    }

    func check(_ blockers: [SleepBlocker], threshold: TimeInterval) {
        let current = Set(blockers.map(periodID))
        // Forget periods that ended so the set doesn't grow forever.
        notified.formIntersection(current)

        for blocker in blockers where Date.now.timeIntervalSince(blocker.since) >= threshold {
            guard notified.insert(periodID(blocker)).inserted else { continue }

            let content = UNMutableNotificationContent()
            content.title = "\(blocker.name) is keeping your Mac awake"
            content.body = "For \(formatDuration(Date.now.timeIntervalSince(blocker.since), style: .full))"
                + (blocker.reasons.isEmpty ? "" : ": \(blocker.reasons.joined(separator: ", "))")
            let request = UNNotificationRequest(identifier: periodID(blocker), content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request)
        }
    }

    private func periodID(_ blocker: SleepBlocker) -> String {
        "\(blocker.key)|\(blocker.since.timeIntervalSince1970)"
    }

    /// Orexin is always "in the foreground" as a menu bar app, so show banners anyway.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
