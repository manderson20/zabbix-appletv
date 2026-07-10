//
//  DashboardManager.swift
//  DashboardOps
//
//  Created by Codex on 7/7/26.
//

import Foundation

/// Coordinates dashboard discovery and selection for the active provider.
actor DashboardManager {
    private let providerRegistry: ProviderRegistry
    let settingsService: SettingsService
    let zabbixAPIClient: ZabbixAPIClient
    let zabbixSessionService: ZabbixSessionService

    /// Tracks whether `SeverityPalette` has already been populated for this session, so it's
    /// fetched once rather than on every dashboard/refresh load.
    var hasFetchedSeverityPalette = false

    /// Creates a dashboard manager backed by a provider registry and the Zabbix stack.
    init(
        providerRegistry: ProviderRegistry,
        settingsService: SettingsService,
        zabbixAPIClient: ZabbixAPIClient,
        zabbixSessionService: ZabbixSessionService
    ) {
        self.providerRegistry = providerRegistry
        self.settingsService = settingsService
        self.zabbixAPIClient = zabbixAPIClient
        self.zabbixSessionService = zabbixSessionService
    }

    /// Returns providers known to the app shell.
    func availableProviders() async -> [any DashboardProvider] {
        providerRegistry.providers
    }

    /// Loads dashboards for a provider, connecting to Zabbix first if needed.
    func dashboards(for providerKind: DashboardProviderKind) async throws -> [Dashboard] {
        guard providerKind == .zabbix else {
            return []
        }

        guard let configuration = try await settingsService.loadServerConfiguration() else {
            throw DashboardOpsError.missingServerConfiguration
        }

        let (serverBaseURL, authToken) = try await connection()
        let summaries = try await zabbixAPIClient.dashboards(serverBaseURL: serverBaseURL, authToken: authToken)

        return summaries.enumerated().map { index, summary in
            let dashboardID = "\(DashboardProviderKind.zabbix.rawValue).\(summary.dashboardid)"
            let isDefault = configuration.preferredDashboardID.map { $0 == dashboardID } ?? (index == 0)

            return Dashboard(
                providerKind: .zabbix,
                providerDashboardID: summary.dashboardid,
                title: summary.name,
                subtitle: nil,
                url: ZabbixAPIClient.kioskDashboardURL(serverBaseURL: serverBaseURL, dashboardID: summary.dashboardid),
                displaySettings: .standard,
                isDefault: isDefault
            )
        }
    }

    /// Loads a dashboard's widget layout, resolved with the data needed for native rendering.
    ///
    /// Only the dashboard's first page is rendered; multi-page (tabbed) dashboards are a future
    /// enhancement.
    func widgets(forDashboard dashboardID: String) async throws -> [RenderableDashboardWidget] {
        let (serverBaseURL, authToken) = try await connection()
        let detail = try await zabbixAPIClient.dashboardDetail(
            serverBaseURL: serverBaseURL,
            authToken: authToken,
            dashboardID: dashboardID
        )

        guard let widgets = detail.pages.first?.widgets else {
            return []
        }

        return try await renderableWidgets(for: widgets, serverBaseURL: serverBaseURL, authToken: authToken)
    }

    /// Re-resolves data for a subset of a dashboard's widgets, identified by widget ID, without
    /// touching the rest. Used for per-widget periodic refresh driven by each widget's own
    /// Zabbix-configured refresh interval — callers merge the returned widgets back into their
    /// own full widget list.
    func refreshWidgets(_ widgetIDs: Set<String>, forDashboard dashboardID: String) async throws -> [RenderableDashboardWidget] {
        guard !widgetIDs.isEmpty else {
            return []
        }

        let (serverBaseURL, authToken) = try await connection()
        let detail = try await zabbixAPIClient.dashboardDetail(
            serverBaseURL: serverBaseURL,
            authToken: authToken,
            dashboardID: dashboardID
        )

        let matchingWidgets = (detail.pages.first?.widgets ?? []).filter { widgetIDs.contains($0.widgetid) }
        return try await renderableWidgets(for: matchingWidgets, serverBaseURL: serverBaseURL, authToken: authToken)
    }
}
