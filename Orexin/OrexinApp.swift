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
            if blocker.bundleIdentifier != nil, !blocker.isOwnProcess {
                Button("Show \(blocker.name)") {
                    NSRunningApplication(processIdentifier: blocker.pid)?.activate()
                }
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
    /// Menu bar icon: the moon face from the app icon plus a colored status dot. The moon's eyes
    /// are open (and the dot red or orange) while something keeps the Mac awake, and closed
    /// (with a green dot) when it's free to sleep.
    ///
    /// The menu bar renders images as monochrome templates, which would strip the dot's color,
    /// so this is a non-template image that draws the moon in the label color itself.
    static func statusIcon(for status: SleepStatus) -> NSImage {
        let moonSide: CGFloat = 16
        let dotDiameter: CGFloat = 7
        let spacing: CGFloat = 3
        let size = NSSize(width: moonSide + spacing + dotDiameter, height: moonSide)

        let image = NSImage(size: size, flipped: false) { _ in
            NSColor.labelColor.setFill()
            moonFace(in: NSRect(x: 0, y: 0, width: moonSide, height: moonSide),
                     eyesOpen: status != .clear).fill()

            let dotRect = NSRect(x: moonSide + spacing, y: (size.height - dotDiameter) / 2,
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

    /// A filled circle with the two eyes cut out (even-odd fill), simplified from the app icon.
    private static func moonFace(in rect: NSRect, eyesOpen: Bool) -> NSBezierPath {
        let path = NSBezierPath(ovalIn: rect)
        path.windingRule = .evenOdd

        let radius = rect.width / 2
        // Eye centers and sizes relative to the moon's radius; larger than in the app icon so
        // they stay readable at menu bar size.
        let eyes: [(dx: CGFloat, dy: CGFloat, width: CGFloat, height: CGFloat)] = [
            (-0.28, 0.17, 0.48, 0.60),
            (0.28, 0.24, 0.45, 0.57),
        ]
        for eye in eyes {
            let center = NSPoint(x: rect.midX + eye.dx * radius, y: rect.midY + eye.dy * radius)
            let width = eye.width * radius

            if eyesOpen {
                let height = eye.height * radius
                path.append(NSBezierPath(ovalIn: NSRect(x: center.x - width / 2, y: center.y - height / 2,
                                                        width: width, height: height)))
            } else {
                // Closed eye: a thick downward-curved lid, like "︶".
                let lidWidth = width * 0.95
                let thickness = max(rect.width * 0.13, 1.6)
                let sag = lidWidth * 0.45
                let left = NSPoint(x: center.x - lidWidth / 2, y: center.y)
                let right = NSPoint(x: center.x + lidWidth / 2, y: center.y)
                let lid = NSBezierPath()
                lid.move(to: left)
                lid.curve(to: right,
                          controlPoint1: NSPoint(x: left.x + lidWidth * 0.2, y: center.y - sag),
                          controlPoint2: NSPoint(x: right.x - lidWidth * 0.2, y: center.y - sag))
                lid.curve(to: left,
                          controlPoint1: NSPoint(x: right.x - lidWidth * 0.2, y: center.y - sag + thickness * 1.6),
                          controlPoint2: NSPoint(x: left.x + lidWidth * 0.2, y: center.y - sag + thickness * 1.6))
                lid.close()
                path.append(lid)
            }
        }
        return path
    }

    func resized(to side: CGFloat) -> NSImage {
        let copy = self.copy() as! NSImage
        copy.size = NSSize(width: side, height: side)
        return copy
    }
}
