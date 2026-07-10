//
//  SeverityPalette.swift
//  DashboardOps
//
//  Created by Codex on 7/8/26.
//

import SwiftUI

/// Server-configured severity colors and names (Zabbix's "Trigger displaying options"), cached
/// here so view code's per-severity color lookups don't need every problem/trigger model to
/// carry its own resolved color. Defaults match Zabbix's stock palette until a live fetch (done
/// once per dashboard load) completes, so the first paint still looks right even before the
/// fetch lands.
@MainActor
enum SeverityPalette {
    private static let defaultHex = ["97AAB3", "7499FF", "FFC859", "FFA059", "E97659", "E45959"]
    private static let defaultNames = ["Not classified", "Information", "Warning", "Average", "High", "Disaster"]

    private static var hexBySeverity = defaultHex
    private static var namesBySeverity = defaultNames

    /// Updates the cached palette from a live server fetch.
    static func update(hex: [String], names: [String]) {
        guard hex.count == 6, names.count == 6 else { return }
        hexBySeverity = hex
        namesBySeverity = names
    }

    static func color(for severity: Int) -> Color {
        let hex = hexBySeverity.indices.contains(severity)
            ? hexBySeverity[severity]
            : (defaultHex.indices.contains(severity) ? defaultHex[severity] : "97AAB3")
        return Color(hex: hex) ?? .gray
    }

    static func name(for severity: Int) -> String {
        if namesBySeverity.indices.contains(severity) {
            return namesBySeverity[severity]
        }
        return defaultNames.indices.contains(severity) ? defaultNames[severity] : "Unknown"
    }
}
