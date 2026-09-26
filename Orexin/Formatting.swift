//
//  Formatting.swift
//  Orexin
//

import Foundation

/// Formats a duration like "1 hr, 12 min" (`.short`) or "1 hour, 12 minutes" (`.full`).
/// Durations under a minute read as "under a minute".
func formatDuration(_ interval: TimeInterval, style: DateComponentsFormatter.UnitsStyle = .short) -> String {
    guard interval >= 60 else { return "under a minute" }
    let formatter = DateComponentsFormatter()
    formatter.allowedUnits = interval >= 24 * 60 * 60 ? [.day, .hour] : [.hour, .minute]
    formatter.unitsStyle = style
    formatter.maximumUnitCount = 2
    return formatter.string(from: interval) ?? ""
}
