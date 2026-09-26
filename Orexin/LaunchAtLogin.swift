//
//  LaunchAtLogin.swift
//  Orexin
//

import Observation
import OSLog
import ServiceManagement

/// Registers the app as a login item via `SMAppService`.
@MainActor
@Observable
final class LaunchAtLogin {
    private(set) var isEnabled = false

    init() {
        refresh()
    }

    func refresh() {
        isEnabled = SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            Logger().error("Failed to update login item: \(error.localizedDescription)")
        }
        refresh()
    }
}
