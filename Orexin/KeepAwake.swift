//
//  KeepAwake.swift
//  Orexin
//

import Foundation
import IOKit.pwr_mgt
import Observation
import OSLog

/// Keeps the Mac from idle sleeping, like `caffeinate -i`, by holding a power assertion.
/// Can be on indefinitely or for a limited time.
@MainActor
@Observable
final class KeepAwake {
    static let assertionName = "Orexin: Keep Mac Awake"

    private var assertionID: IOPMAssertionID?
    /// When a timed keep-awake ends, or `nil` if it's on indefinitely (or off).
    private(set) var endDate: Date?
    private var expiryTimer: Timer?

    var isEnabled: Bool { assertionID != nil }

    /// Turns keep-awake on, for `duration` seconds or indefinitely if `nil`.
    func enable(for duration: TimeInterval? = nil) {
        if assertionID == nil {
            var id = IOPMAssertionID(0)
            let result = IOPMAssertionCreateWithName(
                "PreventUserIdleSystemSleep" as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                Self.assertionName as CFString,
                &id
            )
            guard result == kIOReturnSuccess else {
                Logger().error("Failed to create power assertion: \(result)")
                return
            }
            assertionID = id
        }

        expiryTimer?.invalidate()
        expiryTimer = nil
        endDate = duration.map { Date.now.addingTimeInterval($0) }

        if endDate != nil {
            // Check against the wall clock rather than firing once after `duration`: timers
            // don't advance while the Mac is asleep (e.g. with the lid closed).
            expiryTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.disableIfExpired() }
            }
        }
    }

    func disable() {
        expiryTimer?.invalidate()
        expiryTimer = nil
        endDate = nil
        if let id = assertionID {
            IOPMAssertionRelease(id)
            assertionID = nil
        }
    }

    private func disableIfExpired() {
        if let endDate, endDate <= .now { disable() }
    }
}
