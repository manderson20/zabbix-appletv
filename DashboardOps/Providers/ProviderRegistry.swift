//
//  ProviderRegistry.swift
//  DashboardOps
//
//  Created by Codex on 7/7/26.
//

import Foundation

/// Catalog of dashboard providers known to the application.
nonisolated struct ProviderRegistry: Sendable {
    /// Providers available to settings and future dashboard managers.
    let providers: [any DashboardProvider]

    /// Standard provider catalog for DashboardOps.
    static let standard = ProviderRegistry(
        providers: [
            ZabbixProvider(),
            GrafanaProvider(),
            WebDashboardProvider(),
            PrintOpsProvider(),
            BuslineProvider(),
            UniFiProvider()
        ]
    )
}
