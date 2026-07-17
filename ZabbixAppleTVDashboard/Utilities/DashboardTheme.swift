//
//  DashboardTheme.swift
//  ZabbixAppleTVDashboard
//
//  Created by Codex on 7/7/26.
//

import SwiftUI

/// Shared visual tokens for the tvOS interface.
enum DashboardTheme {
    /// Primary accent color.
    static let accent = Color.blue

    /// Full-screen app background.
    static let background = Color.black

    /// Card surface color.
    static let cardBackground = Color(red: 0.10, green: 0.10, blue: 0.12)

    /// Secondary card surface color.
    static let secondaryCardBackground = Color(red: 0.15, green: 0.15, blue: 0.18)

    /// Primary text color.
    static let primaryText = Color.white

    /// Secondary text color.
    static let secondaryText = Color.white.opacity(0.68)

    /// Standard card radius.
    static let cardCornerRadius: CGFloat = 8

    /// Standard horizontal screen padding for 16:9 layouts.
    static let horizontalScreenPadding: CGFloat = 88

    /// Standard vertical screen padding for 16:9 layouts.
    static let verticalScreenPadding: CGFloat = 58
}

extension Color {
    /// Creates a color from a "RRGGBB" hex string, as used throughout Zabbix's widget fields
    /// (series colors, thresholds, background colors).
    ///
    /// `nonisolated` because it's pure string→RGB math with no main-actor state: under the
    /// project's default main-actor isolation it would otherwise be implicitly main-actor-isolated,
    /// which warns when it's passed as a plain function value (e.g. `flatMap(Color.init(hex:))`).
    nonisolated init?(hex: String) {
        var sanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if sanitized.hasPrefix("#") {
            sanitized.removeFirst()
        }

        guard sanitized.count == 6, let value = UInt32(sanitized, radix: 16) else {
            return nil
        }

        let red = Double((value >> 16) & 0xFF) / 255
        let green = Double((value >> 8) & 0xFF) / 255
        let blue = Double(value & 0xFF) / 255
        self = Color(red: red, green: green, blue: blue)
    }
}
