//
//  KeepAwake.swift
//  SleepBlocker
//

import IOKit.pwr_mgt
import Observation
import OSLog

/// Keeps the Mac from idle sleeping, like `caffeinate -i`, by holding a power assertion.
@MainActor
@Observable
final class KeepAwake {
    static let assertionName = "Sleep Blocker: Keep Mac Awake"

    private var assertionID: IOPMAssertionID?

    var isEnabled: Bool { assertionID != nil }

    func setEnabled(_ enabled: Bool) {
        if enabled, assertionID == nil {
            var id = IOPMAssertionID(0)
            let result = IOPMAssertionCreateWithName(
                "PreventUserIdleSystemSleep" as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                Self.assertionName as CFString,
                &id
            )
            if result == kIOReturnSuccess {
                assertionID = id
            } else {
                Logger().error("Failed to create power assertion: \(result)")
            }
        } else if !enabled, let id = assertionID {
            IOPMAssertionRelease(id)
            assertionID = nil
        }
    }
}
