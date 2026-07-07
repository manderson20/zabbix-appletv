//
//  GrafanaProvider.swift
//  DashboardOps
//
//  Created by Codex on 7/7/26.
//

import Foundation

/// Provider metadata reserved for a future Grafana integration.
nonisolated struct GrafanaProvider: DashboardProvider {
    /// Stable provider identifier.
    let id = DashboardProviderKind.grafana.rawValue

    /// Human-readable provider name.
    let displayName = "Grafana"

    /// Provider family.
    let kind = DashboardProviderKind.grafana

    /// Grafana is planned for a later release.
    let supportStatus = ProviderSupportStatus.planned
}
