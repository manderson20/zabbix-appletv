//
//  Dashboard.swift
//  ZabbixAppleTVDashboard
//
//  Created by Codex on 7/7/26.
//

import Foundation

/// Represents a dashboard made available by a provider such as Zabbix.
nonisolated struct Dashboard: Identifiable, Codable, Equatable, Sendable {
    /// Provider that owns the dashboard.
    var providerKind: DashboardProviderKind

    /// Provider-specific dashboard identifier.
    var providerDashboardID: String

    /// Display title shown in dashboard lists and status overlays.
    var title: String

    /// Optional contextual label for the dashboard.
    var subtitle: String?

    /// Kiosk-mode dashboard viewer URL.
    var url: URL?

    /// Display behavior for the dashboard viewer.
    var displaySettings: DashboardDisplaySettings

    /// Indicates whether this dashboard should open automatically.
    var isDefault: Bool

    /// Stable identifier derived from the provider and its dashboard identifier.
    ///
    /// Dashboards are refetched from the provider on every load, so identity is derived
    /// rather than stored to stay stable across fetches (unlike a freshly generated UUID).
    var id: String { "\(providerKind.rawValue).\(providerDashboardID)" }
}
