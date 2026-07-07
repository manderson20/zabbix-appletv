//
//  WebDashboardProvider.swift
//  DashboardOps
//
//  Created by Codex on 7/7/26.
//

import Foundation

/// Provider metadata reserved for custom web dashboards.
nonisolated struct WebDashboardProvider: DashboardProvider {
    /// Stable provider identifier.
    let id = DashboardProviderKind.webDashboard.rawValue

    /// Human-readable provider name.
    let displayName = "Web Dashboard"

    /// Provider family.
    let kind = DashboardProviderKind.webDashboard

    /// Custom web dashboards are planned for a later release.
    let supportStatus = ProviderSupportStatus.planned
}
