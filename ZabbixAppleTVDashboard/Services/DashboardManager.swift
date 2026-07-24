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

    /// Data-driven default title for the widget most recently resolved — Zabbix's own default
    /// headers name the data, not the widget type ("BSD-DNS1: Available memory", a clock's
    /// "Local"). A resolver that knows the better title sets this synchronously immediately before
    /// returning, and `renderableWidgets` consumes (and clears) it synchronously right after each
    /// `resolveWidgetKind` returns; with no suspension point between set→return→read on this
    /// actor, concurrent resolutions can't cross-contaminate. Nil means "use the widget-type
    /// fallback title".
    var pendingDefaultTitle: String?

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

    /// Re-reads a dashboard for a viewer that already has it on screen.
    ///
    /// The page and widget *layout* always comes back current, because it all arrives with the one
    /// `dashboard.get` this makes either way — so a widget added, deleted, moved or resized in
    /// Zabbix is reflected without the viewer reloading from scratch. Widget *data* is the
    /// expensive part (a fetch per widget) and is limited to widgets that are due for their own
    /// configured refresh (`dueWidgetIDs`) plus any widget the caller has never seen — anything
    /// absent from `knownWidgetIDs`, which is exactly a widget added since the viewer loaded and
    /// therefore has no data to carry over.
    func refreshedDashboard(
        forDashboardID dashboardID: String,
        dueWidgetIDs: Set<String>,
        knownWidgetIDs: Set<String>
    ) async throws -> RefreshedDashboard {
        let (serverBaseURL, authToken) = try await connection()
        let detail = try await zabbixAPIClient.dashboardDetail(
            serverBaseURL: serverBaseURL,
            authToken: authToken,
            dashboardID: dashboardID
        )

        let widgetsNeedingData = detail.pages.flatMap(\.widgets).filter {
            dueWidgetIDs.contains($0.widgetid) || !knownWidgetIDs.contains($0.widgetid)
        }
        let resolved = try await renderableWidgets(
            for: widgetsNeedingData,
            serverBaseURL: serverBaseURL,
            authToken: authToken
        )
        let resolvedByID = Dictionary(resolved.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        let defaultDisplaySeconds = max(detail.display_period?.intValue ?? 30, 1)
        let pages = detail.pages.enumerated().map { index, page in
            let ownDisplaySeconds = page.display_period?.intValue ?? 0
            return RefreshedDashboardPage(
                id: page.dashboard_pageid ?? "\(index)",
                name: page.name,
                displaySeconds: ownDisplaySeconds > 0 ? ownDisplaySeconds : defaultDisplaySeconds,
                widgets: page.widgets.map { widget in
                    RefreshedDashboardWidget(
                        id: widget.widgetid,
                        customTitle: widget.name?.isEmpty == false ? widget.name : nil,
                        frame: DashboardWidgetFrame(
                            x: widget.x.intValue,
                            y: widget.y.intValue,
                            width: widget.width.intValue,
                            height: widget.height.intValue
                        ),
                        refreshIntervalSeconds: Self.refreshIntervalSeconds(from: widget.fields),
                        hasHiddenHeader: widget.view_mode?.intValue == 1,
                        resolved: resolvedByID[widget.widgetid]
                    )
                }
            )
        }

        return RefreshedDashboard(pages: pages, autoRotatesPages: detail.auto_start?.intValue == 1)
    }
}
