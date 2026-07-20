//
//  ProblemTimelineFormat.swift
//  ZabbixAppleTVDashboard
//
//  Created by Claude on 7/20/26.
//

import Foundation

/// Formats the Problems widget's time-related columns the way Zabbix's frontend does — all three
/// verified against the live widget: the Time column shows a bare clock for problems that started
/// today ("08:54:53 AM") and a full date-time for older ones ("2026-07-19 02:03:50 AM"); the
/// Duration column is Zabbix's age string of up to three consecutive units starting at the
/// largest non-zero one ("47s", "2h 28m 7s", "1d 6h 51m"); and the timeline inserts a separator
/// between rows when they cross an hour ("08:00") or day boundary ("Today", "Yesterday", or the
/// date), labeled for the newer side of the boundary.
nonisolated enum ProblemTimelineFormat {
    private static func formatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = format
        return formatter
    }

    /// The Time column: clock only for today, date-prefixed otherwise.
    static func timeLabel(for date: Date, now: Date, calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) {
            return formatter("hh:mm:ss a").string(from: date)
        }
        return formatter("yyyy-MM-dd hh:mm:ss a").string(from: date)
    }

    /// The Duration column: Zabbix's age format — the three consecutive units starting at the
    /// largest non-zero one, zeros in the middle kept ("1d 0h 51m"), seconds only below a minute.
    static func ageLabel(from start: Date, to now: Date) -> String {
        let totalSeconds = max(0, Int(now.timeIntervalSince(start)))
        let units: [(size: Int, suffix: String)] = [
            (31_536_000, "y"), (2_592_000, "M"), (86_400, "d"), (3600, "h"), (60, "m"), (1, "s"),
        ]

        guard let firstIndex = units.firstIndex(where: { totalSeconds / $0.size > 0 }) else {
            return "0s"
        }

        var remainder = totalSeconds
        var parts: [String] = []
        for unit in units[firstIndex..<min(firstIndex + 3, units.count)] {
            parts.append("\(remainder / unit.size)\(unit.suffix)")
            remainder %= unit.size
        }
        return parts.joined(separator: " ")
    }

    /// The timeline separator between a newer and an older row, or nil when they fall within the
    /// same hour. Crossing a day boundary labels the newer row's day — "Today", "Yesterday", or
    /// its date; crossing only an hour boundary labels the newer row's whole hour ("08:00").
    static func separatorLabel(newer: Date, older: Date, now: Date, calendar: Calendar = .current) -> String? {
        if !calendar.isDate(newer, inSameDayAs: older) {
            if calendar.isDate(newer, inSameDayAs: now) { return "Today" }
            if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
               calendar.isDate(newer, inSameDayAs: yesterday) { return "Yesterday" }
            return formatter("yyyy-MM-dd").string(from: newer)
        }
        if calendar.component(.hour, from: newer) != calendar.component(.hour, from: older) {
            return formatter("hh:00").string(from: newer)
        }
        return nil
    }
}
