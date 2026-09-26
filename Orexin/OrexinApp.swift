//
//  OrexinApp.swift
//  Orexin
//
//  Created by Ergün Kayis on 26.09.26.
//

import SwiftUI

@main
struct OrexinApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuContent(model: model)
        } label: {
            Image(nsImage: .statusIcon(for: model.status))
        }
        .menuBarExtraStyle(.menu)

        Window("Sleep History", id: "history") {
            HistoryView(model: model)
        }
        .defaultSize(width: 480, height: 560)
        .defaultLaunchBehavior(.suppressed)
    }
}

private struct MenuContent: View {
    @Bindable var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let apps = model.appBlockers
        let system = model.systemBlockers
        let ignored = model.ignoredBlockers

        if apps.isEmpty {
            Text("No apps are preventing sleep")
        } else {
            Section("Apps preventing sleep") {
                ForEach(apps) { BlockerRow(blocker: $0, model: model) }
            }
        }

        if model.includeSystemProcesses {
            Divider()
            if system.isEmpty {
                Text("No system processes are preventing sleep")
            } else {
                Section("System processes") {
                    ForEach(system) { BlockerRow(blocker: $0, model: model) }
                }
            }
        }

        if !ignored.isEmpty {
            Divider()
            Menu("Ignored (\(ignored.count))") {
                ForEach(ignored) { blocker in
                    Button("Stop Ignoring \(blocker.name)") { model.stopIgnoring(blocker) }
                }
            }
        }

        Divider()
        KeepAwakeMenu(keepAwake: model.keepAwake)
        Button("Sleep History…") {
            openWindow(id: "history")
            NSApp.activate()
        }
        .keyboardShortcut("y")

        Divider()
        Picker("Notify When Blocked For", selection: $model.alertMinutes) {
            Text("Off").tag(0)
            Divider()
            Text("15 Minutes").tag(15)
            Text("30 Minutes").tag(30)
            Text("1 Hour").tag(60)
            Text("2 Hours").tag(120)
        }
        Toggle("Show System Processes", isOn: $model.includeSystemProcesses)
        Toggle("Launch at Login", isOn: Binding(
            get: { model.launchAtLogin.isEnabled },
            set: { model.launchAtLogin.setEnabled($0) }
        ))
        Button("Refresh") { model.monitor.refresh() }
            .keyboardShortcut("r")
        Divider()
        Button("Quit Orexin") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }
}

private struct KeepAwakeMenu: View {
    let keepAwake: KeepAwake

    private static let durations: [(title: String, minutes: Int)] = [
        ("15 Minutes", 15), ("30 Minutes", 30), ("1 Hour", 60), ("2 Hours", 120), ("5 Hours", 300),
    ]

    private var title: String {
        guard keepAwake.isEnabled else { return "Keep Mac Awake" }
        guard let endDate = keepAwake.endDate else { return "Keep Mac Awake: On" }
        return "Keep Mac Awake: Until \(endDate.formatted(date: .omitted, time: .shortened))"
    }

    var body: some View {
        Menu(title) {
            if keepAwake.isEnabled {
                Button("Turn Off") { keepAwake.disable() }
                    .keyboardShortcut("k")
                Divider()
            }
            Button("Until Turned Off") { keepAwake.enable() }
            Section("For") {
                ForEach(Self.durations, id: \.minutes) { duration in
                    Button(duration.title) { keepAwake.enable(for: TimeInterval(duration.minutes * 60)) }
                }
            }
        }
    }
}

private struct BlockerRow: View {
    let blocker: SleepBlocker
    let model: AppModel

    private var subtitle: String {
        let kind = blocker.kind == .display ? "Keeps display awake" : "Keeps system awake"
        return "\(kind) · \(formatDuration(Date.now.timeIntervalSince(blocker.since)))"
    }

    var body: some View {
        Menu {
            ForEach(blocker.reasons, id: \.self) { Text($0) }
            Text("Since \(blocker.since.formatted(date: .omitted, time: .shortened))")
            Text("PID \(blocker.pid)")
            Divider()
            if blocker.isApp, !blocker.isOwnProcess {
                Button("Show \(blocker.name)") {
                    NSRunningApplication(processIdentifier: blocker.pid)?.activate()
                }
                Button("Quit \(blocker.name)") { model.quit(blocker) }
            }
            if !blocker.isOwnProcess {
                Button("Ignore \(blocker.name)") { model.ignore(blocker) }
            }
        } label: {
            if let icon = blocker.icon {
                Image(nsImage: icon.resized(to: 16))
            }
            Text(blocker.name)
            Text(subtitle)
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
