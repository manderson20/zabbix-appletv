//
//  DashboardTheme.swift
//  DashboardOps
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
