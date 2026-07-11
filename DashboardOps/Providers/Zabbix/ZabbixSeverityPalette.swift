//
//  ZabbixSeverityPalette.swift
//  DashboardOps
//
//  Created by Codex on 7/8/26.
//

import Foundation

/// The server's "Trigger displaying options" (Administration -> General), as returned by
/// `settings.get` — severity colors/names plus how long a new problem should visually "blink" to
/// draw attention.
nonisolated struct ZabbixSeverityPalette: Decodable, Sendable {
    let severity_color_0: String
    let severity_color_1: String
    let severity_color_2: String
    let severity_color_3: String
    let severity_color_4: String
    let severity_color_5: String

    let severity_name_0: String
    let severity_name_1: String
    let severity_name_2: String
    let severity_name_3: String
    let severity_name_4: String
    let severity_name_5: String

    /// How long a newly-started problem should blink, as a Zabbix "simple time period" string
    /// (e.g. "2m", "30s") rather than a plain integer — verified live: "2m" on this server.
    let blink_period: String

    /// Colors in ascending severity order (0 = not classified ... 5 = disaster).
    var colorsBySeverity: [String] {
        [severity_color_0, severity_color_1, severity_color_2, severity_color_3, severity_color_4, severity_color_5]
    }

    /// Names in ascending severity order (0 = not classified ... 5 = disaster).
    var namesBySeverity: [String] {
        [severity_name_0, severity_name_1, severity_name_2, severity_name_3, severity_name_4, severity_name_5]
    }

    /// `blink_period` parsed into seconds. Falls back to Zabbix's own stock default (2 minutes)
    /// if the string is in an unrecognized shape.
    var blinkPeriodSeconds: Int {
        Self.parseDuration(blink_period) ?? 120
    }

    private static func parseDuration(_ raw: String) -> Int? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard let unit = trimmed.last, let magnitude = Int(trimmed.dropLast()) else {
            return Int(trimmed)
        }

        switch unit {
        case "s": return magnitude
        case "m": return magnitude * 60
        case "h": return magnitude * 3600
        case "d": return magnitude * 86400
        case "w": return magnitude * 604800
        default: return Int(trimmed)
        }
    }
}
