//
//  ZabbixSeverityPalette.swift
//  DashboardOps
//
//  Created by Codex on 7/8/26.
//

import Foundation

/// The server's configured trigger severity colors and names, as returned by `settings.get`.
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

    /// Colors in ascending severity order (0 = not classified ... 5 = disaster).
    var colorsBySeverity: [String] {
        [severity_color_0, severity_color_1, severity_color_2, severity_color_3, severity_color_4, severity_color_5]
    }

    /// Names in ascending severity order (0 = not classified ... 5 = disaster).
    var namesBySeverity: [String] {
        [severity_name_0, severity_name_1, severity_name_2, severity_name_3, severity_name_4, severity_name_5]
    }
}
