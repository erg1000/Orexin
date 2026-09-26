//
//  HistoryView.swift
//  Orexin
//

import SwiftUI

/// Shows when the Mac slept and woke, and what kept it awake in between.
struct HistoryView: View {
    let model: AppModel

    private var history: SleepHistory { model.history }

    private func isVisible(_ entry: HistoryEntry) -> Bool {
        entry.kind != .blocked || entry.isApp || model.includeSystemProcesses
    }

    private var ongoing: [HistoryEntry] {
        history.ongoing.values.filter(isVisible).sorted { $0.start < $1.start }
    }

    /// Finished entries grouped by day, newest day and newest entry first.
    private var days: [(day: Date, entries: [HistoryEntry])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: history.entries.filter(isVisible)) { calendar.startOfDay(for: $0.start) }
        return grouped
            .map { (day: $0.key, entries: $0.value.sorted { $0.start > $1.start }) }
            .sorted { $0.day > $1.day }
    }

    private func dayTitle(_ day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }

    var body: some View {
        // Re-render every minute so ongoing durations stay current.
        TimelineView(.periodic(from: .now, by: 60)) { _ in
            if ongoing.isEmpty && days.isEmpty {
                ContentUnavailableView(
                    "No History Yet",
                    systemImage: "moon.zzz",
                    description: Text("Orexin records what keeps your Mac awake for longer than a minute, and when it sleeps and wakes.")
                )
            } else {
                List {
                    if !ongoing.isEmpty {
                        Section("Now") {
                            ForEach(ongoing) { HistoryRow(entry: $0) }
                        }
                    }
                    ForEach(days, id: \.day) { day in
                        Section(dayTitle(day.day)) {
                            ForEach(day.entries) { HistoryRow(entry: $0) }
                        }
                    }
                }
            }
        }
        .frame(minWidth: 380, minHeight: 300)
        .toolbar {
            Button("Clear History", systemImage: "trash") { history.clear() }
                .disabled(history.entries.isEmpty)
        }
    }
}

private struct HistoryRow: View {
    let entry: HistoryEntry

    var body: some View {
        switch entry.kind {
        case .sleep:
            row(title: "Mac went to sleep", systemImage: "moon.fill", tint: .indigo)
        case .wake:
            row(title: "Mac woke up", systemImage: "sun.max.fill", tint: .orange)
        case .blocked:
            HStack(alignment: .firstTextBaseline) {
                appIcon
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(entry.name ?? "Unknown") kept the Mac awake")
                    if !entry.reasons.isEmpty {
                        Text(entry.reasons.joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(timeRange)
                        .monospacedDigit()
                    Text(formatDuration(entry.duration))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var timeRange: String {
        let start = entry.start.formatted(date: .omitted, time: .shortened)
        guard let end = entry.end else { return "since \(start)" }
        return "\(start) – \(end.formatted(date: .omitted, time: .shortened))"
    }

    @ViewBuilder
    private var appIcon: some View {
        if entry.isApp, let key = entry.key,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: key) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .frame(width: 18, height: 18)
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 4 }
        } else {
            Image(systemName: "gearshape")
                .foregroundStyle(.secondary)
                .frame(width: 18)
        }
    }

    private func row(title: String, systemImage: String, tint: Color) -> some View {
        HStack {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
                .frame(width: 18)
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(entry.start.formatted(date: .omitted, time: .shortened))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }
}
