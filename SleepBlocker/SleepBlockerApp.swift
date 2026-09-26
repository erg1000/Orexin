//
//  SleepBlockerApp.swift
//  SleepBlocker
//
//  Created by Ergün Kayis on 26.09.26.
//

import SwiftUI

@main
struct SleepBlockerApp: App {
    @State private var monitor = SleepAssertionMonitor()
    @State private var launchAtLogin = LaunchAtLogin()
    @State private var keepAwake = KeepAwake()
    @AppStorage("includeSystemProcesses") private var includeSystemProcesses = false

    private var status: SleepStatus {
        if !monitor.appBlockers.isEmpty { return .blockedByApp }
        if includeSystemProcesses, !monitor.systemBlockers.isEmpty { return .blockedBySystem }
        return .clear
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContent(
                monitor: monitor,
                launchAtLogin: launchAtLogin,
                keepAwake: keepAwake,
                includeSystemProcesses: $includeSystemProcesses
            )
        } label: {
            Image(nsImage: .statusIcon(for: status))
        }
        .menuBarExtraStyle(.menu)
    }
}

/// What the menu bar dot shows.
private enum SleepStatus {
    /// Nothing relevant is preventing sleep (green).
    case clear
    /// Only system processes are preventing sleep (orange).
    case blockedBySystem
    /// At least one app is preventing sleep (red).
    case blockedByApp
}

private struct MenuContent: View {
    let monitor: SleepAssertionMonitor
    let launchAtLogin: LaunchAtLogin
    let keepAwake: KeepAwake
    @Binding var includeSystemProcesses: Bool

    var body: some View {
        let apps = monitor.appBlockers
        let system = monitor.systemBlockers

        if apps.isEmpty {
            Text("No apps are preventing sleep")
        } else {
            Section("Apps preventing sleep") {
                ForEach(apps) { BlockerRow(blocker: $0) }
            }
        }

        if includeSystemProcesses {
            Divider()
            if system.isEmpty {
                Text("No system processes are preventing sleep")
            } else {
                Section("System processes") {
                    ForEach(system) { BlockerRow(blocker: $0) }
                }
            }
        }

        Divider()
        Toggle("Keep Mac Awake", isOn: Binding(
            get: { keepAwake.isEnabled },
            set: {
                keepAwake.setEnabled($0)
                monitor.refresh()
            }
        ))
        .keyboardShortcut("k")

        Divider()
        Toggle("Show System Processes", isOn: $includeSystemProcesses)
        Toggle("Launch at Login", isOn: Binding(
            get: { launchAtLogin.isEnabled },
            set: { launchAtLogin.setEnabled($0) }
        ))
        Button("Refresh") { monitor.refresh() }
            .keyboardShortcut("r")
        Divider()
        Button("Quit Sleep Blocker") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }
}

private struct BlockerRow: View {
    let blocker: SleepBlocker

    var body: some View {
        Menu {
            ForEach(blocker.reasons, id: \.self) { Text($0) }
            Divider()
            Text("PID \(blocker.pid)")
            if blocker.isApp {
                Button("Show App") {
                    NSRunningApplication(processIdentifier: blocker.pid)?.activate()
                }
            }
        } label: {
            if let icon = blocker.icon {
                Image(nsImage: icon.resized(to: 16))
            }
            Text(blocker.name)
            Text(blocker.kind == .display ? "Keeps display awake" : "Keeps system awake")
        }
    }
}

private extension NSImage {
    /// Menu bar icon with a colored status dot: red when an app prevents sleep, orange when only
    /// system processes do, green otherwise.
    ///
    /// The menu bar renders images as monochrome templates, which would strip the dot's color,
    /// so this is a non-template image that draws the symbol in the label color itself.
    static func statusIcon(for status: SleepStatus) -> NSImage {
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
            .applying(NSImage.SymbolConfiguration(paletteColors: [.labelColor]))
        let symbol = NSImage(systemSymbolName: "moon.zzz", accessibilityDescription: nil)?
            .withSymbolConfiguration(config) ?? NSImage()

        let dotDiameter: CGFloat = 7
        let spacing: CGFloat = 3
        let size = NSSize(width: symbol.size.width + spacing + dotDiameter,
                          height: max(symbol.size.height, dotDiameter))

        let image = NSImage(size: size, flipped: false) { _ in
            symbol.draw(in: NSRect(x: 0, y: (size.height - symbol.size.height) / 2,
                                   width: symbol.size.width, height: symbol.size.height))
            let dotRect = NSRect(x: symbol.size.width + spacing, y: (size.height - dotDiameter) / 2,
                                 width: dotDiameter, height: dotDiameter)
            switch status {
            case .clear: NSColor.systemGreen.setFill()
            case .blockedBySystem: NSColor.systemOrange.setFill()
            case .blockedByApp: NSColor.systemRed.setFill()
            }
            NSBezierPath(ovalIn: dotRect).fill()
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = switch status {
        case .clear: "Nothing is preventing sleep"
        case .blockedBySystem: "System processes are preventing sleep"
        case .blockedByApp: "Apps are preventing sleep"
        }
        return image
    }

    func resized(to side: CGFloat) -> NSImage {
        let copy = self.copy() as! NSImage
        copy.size = NSSize(width: side, height: side)
        return copy
    }
}
