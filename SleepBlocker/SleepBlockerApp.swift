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
    @AppStorage("includeSystemProcesses") private var includeSystemProcesses = false

    private var relevantBlockers: [SleepBlocker] {
        includeSystemProcesses ? monitor.blockers : monitor.appBlockers
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContent(monitor: monitor, includeSystemProcesses: $includeSystemProcesses)
        } label: {
            Image(nsImage: .statusIcon(isBlocked: !relevantBlockers.isEmpty))
        }
        .menuBarExtraStyle(.menu)
    }
}

private struct MenuContent: View {
    let monitor: SleepAssertionMonitor
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
        Toggle("Show System Processes", isOn: $includeSystemProcesses)
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
    /// Menu bar icon with a colored status dot: red when something prevents sleep, green otherwise.
    ///
    /// The menu bar renders images as monochrome templates, which would strip the dot's color,
    /// so this is a non-template image that draws the symbol in the label color itself.
    static func statusIcon(isBlocked: Bool) -> NSImage {
        let symbolName = isBlocked ? "cup.and.saucer.fill" : "moon.zzz"
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
            .applying(NSImage.SymbolConfiguration(paletteColors: [.labelColor]))
        let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
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
            (isBlocked ? NSColor.systemRed : NSColor.systemGreen).setFill()
            NSBezierPath(ovalIn: dotRect).fill()
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = isBlocked ? "Sleep is being prevented" : "Nothing is preventing sleep"
        return image
    }

    func resized(to side: CGFloat) -> NSImage {
        let copy = self.copy() as! NSImage
        copy.size = NSSize(width: side, height: side)
        return copy
    }
}
