//
//  DashboardDisplaySettings.swift
//  DashboardOps
//
//  Created by Codex on 7/7/26.
//

import Foundation

/// Stores display preferences for long-running dashboard playback.
nonisolated struct DashboardDisplaySettings: Codable, Equatable, Sendable {
    /// Number of seconds between dashboard refresh attempts.
    var refreshIntervalSeconds: TimeInterval

    /// Indicates whether the viewer should show a lightweight status overlay.
    var showsStatusOverlay: Bool

    /// Indicates whether dashboards should consume the full Apple TV viewport.
    var usesFullScreen: Bool

    /// Indicates whether the viewer should prefer kiosk-style behavior.
    var isKioskModeEnabled: Bool

    /// Indicates whether the app should try to keep the display awake.
    var preventsDisplaySleep: Bool
}

nonisolated extension DashboardDisplaySettings {
    /// Default display settings for unattended, long-running kiosk playback.
    static let standard = DashboardDisplaySettings(
        refreshIntervalSeconds: 60,
        showsStatusOverlay: false,
        usesFullScreen: true,
        isKioskModeEnabled: true,
        preventsDisplaySleep: true
    )
}
