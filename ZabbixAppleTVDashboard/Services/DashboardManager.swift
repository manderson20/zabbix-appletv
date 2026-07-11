//
//  DashboardManager.swift
//  ZabbixAppleTVDashboard
//
//  Created by Codex on 7/7/26.
//

import Foundation

/// Coordinates dashboard discovery and selection for the active provider.
actor DashboardManager {
    let settingsService: SettingsService
    let zabbixAPIClient: ZabbixAPIClient
    let zabbixSessionService: ZabbixSessionService

    /// Tracks whether `SeverityPalette` has already been populated for this session, so it's
    /// fetched once rather than on every dashboard/refresh load.
    var hasFetchedSeverityPalette = false

    /// Creates a dashboard manager backed by the Zabbix stack.
    init(
        settingsService: SettingsService,
        zabbixAPIClient: ZabbixAPIClient,
        zabbixSessionService: ZabbixSessionService
    ) {
        self.settingsService = settingsService
        self.zabbixAPIClient = zabbixAPIClient
        self.zabbixSessionService = zabbixSessionService
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

    /// Loads a dashboard's full page layout, resolved with the data needed for native rendering.
    /// Every page is resolved (not just the first) so a viewer can rotate through them the same
    /// way Zabbix's own kiosk/slideshow mode does, using each page's own configured duration.
    func renderableDashboard(forDashboardID dashboardID: String) async throws -> RenderableDashboard {
        let (serverBaseURL, authToken) = try await connection()
        let detail = try await zabbixAPIClient.dashboardDetail(
            serverBaseURL: serverBaseURL,
            authToken: authToken,
            dashboardID: dashboardID
        )

        let defaultDisplaySeconds = max(detail.display_period?.intValue ?? 30, 1)

        var pages: [RenderableDashboardPage] = []
        for (index, page) in detail.pages.enumerated() {
            let widgets = try await renderableWidgets(for: page.widgets, serverBaseURL: serverBaseURL, authToken: authToken)
            let ownDisplaySeconds = page.display_period?.intValue ?? 0
            pages.append(
                RenderableDashboardPage(
                    id: page.dashboard_pageid ?? "\(index)",
                    name: page.name,
                    widgets: widgets,
                    displaySeconds: ownDisplaySeconds > 0 ? ownDisplaySeconds : defaultDisplaySeconds
                )
            )
        }

        return RenderableDashboard(pages: pages, autoRotatesPages: detail.auto_start?.intValue == 1)
    }

    /// Re-resolves data for a subset of a dashboard's widgets, identified by widget ID, without
    /// touching the rest. Used for per-widget periodic refresh driven by each widget's own
    /// Zabbix-configured refresh interval — searches every page since the due widgets may not be
    /// on whichever page happens to be visible right now; callers merge the returned widgets back
    /// into their own page/widget list.
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

        let matchingWidgets = detail.pages.flatMap(\.widgets).filter { widgetIDs.contains($0.widgetid) }
        return try await renderableWidgets(for: matchingWidgets, serverBaseURL: serverBaseURL, authToken: authToken)
    }
}
