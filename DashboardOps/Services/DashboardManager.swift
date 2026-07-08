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

        guard let configuration = try await settingsService.loadServerConfiguration(),
              let serverBaseURL = configuration.baseURL else {
            throw DashboardOpsError.missingServerConfiguration
        }

        let session: UserSession
        if let activeSession = await zabbixSessionService.activeSession() {
            session = activeSession
        } else {
            session = try await zabbixSessionService.connect()
        }

        guard let authToken = session.authToken else {
            throw DashboardOpsError.missingCredential
        }

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
        guard let configuration = try await settingsService.loadServerConfiguration(),
              let serverBaseURL = configuration.baseURL else {
            throw DashboardOpsError.missingServerConfiguration
        }

        let session: UserSession
        if let activeSession = await zabbixSessionService.activeSession() {
            session = activeSession
        } else {
            session = try await zabbixSessionService.connect()
        }

        guard let authToken = session.authToken else {
            throw DashboardOpsError.missingCredential
        }

        let detail = try await zabbixAPIClient.dashboardDetail(
            serverBaseURL: serverBaseURL,
            authToken: authToken,
            dashboardID: dashboardID
        )

        guard let widgets = detail.pages.first?.widgets else {
            return []
        }

        var renderableWidgets: [RenderableDashboardWidget] = []
        renderableWidgets.reserveCapacity(widgets.count)

        for widget in widgets {
            let kind = try await resolveWidgetKind(widget, serverBaseURL: serverBaseURL, authToken: authToken)
            renderableWidgets.append(
                RenderableDashboardWidget(
                    id: widget.widgetid,
                    title: widget.name?.isEmpty == false ? widget.name! : widget.type.capitalized,
                    frame: DashboardWidgetFrame(
                        x: widget.x.intValue,
                        y: widget.y.intValue,
                        width: widget.width.intValue,
                        height: widget.height.intValue
                    ),
                    kind: kind
                )
            )
        }

        return renderableWidgets
    }
}
