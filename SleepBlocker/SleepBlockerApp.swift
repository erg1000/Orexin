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
            if relevantBlockers.isEmpty {
                Image(systemName: "moon.zzz")
            } else {
                HStack(spacing: 2) {
                    Image(systemName: "cup.and.saucer.fill")
                    Text("\(relevantBlockers.count)")
                }
            }
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
    func resized(to side: CGFloat) -> NSImage {
        let copy = self.copy() as! NSImage
        copy.size = NSSize(width: side, height: side)
        return copy
    }
}
