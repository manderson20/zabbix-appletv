//
//  DashboardViewerViewModel.swift
//  DashboardOps
//
//  Created by Codex on 7/7/26.
//

import Combine
import Foundation

/// View model for the full-screen dashboard viewer.
@MainActor
final class DashboardViewerViewModel: ObservableObject {
    /// Dashboard title shown above the rendered dashboard.
    @Published private(set) var dashboardTitle = "Zabbix Dashboard"

    /// Current dashboard rendering state.
    @Published private(set) var renderingState: DashboardRenderingState = .idle

    /// Status message shown while the dashboard is not yet ready.
    @Published private(set) var statusMessage = "Preparing dashboard"

    /// Indicates whether the current connection attempt can be retried.
    @Published private(set) var canRetry = false

    /// Dashboard resolved for display.
    @Published private(set) var selectedDashboard: Dashboard?

    /// Widgets resolved for the selected dashboard's first page.
    @Published private(set) var widgets: [RenderableDashboardWidget] = []

    private let dashboardManager: DashboardManager
    private let zabbixSessionService: ZabbixSessionService
    private var hasPrepared = false
    private var explicitDashboard: Dashboard?

    /// Creates a dashboard viewer view model.
    init(dashboardManager: DashboardManager, zabbixSessionService: ZabbixSessionService) {
        self.dashboardManager = dashboardManager
        self.zabbixSessionService = zabbixSessionService
    }

    /// Prepares the viewer by connecting to Zabbix and resolving a dashboard to display.
    func prepareViewer() async {
        guard !hasPrepared else { return }
        hasPrepared = true

        renderingState = .loading
        statusMessage = "Connecting to Zabbix"
        canRetry = false

        do {
            let session = try await zabbixSessionService.connect()
            let versionText = session.serverVersion.map { "Zabbix \($0)" } ?? "Zabbix"

            guard let dashboard = try await resolveDashboard() else {
                dashboardTitle = "\(versionText) Dashboard"
                renderingState = .unavailable
                statusMessage = "No dashboards are available for this Zabbix server."
                canRetry = true
                return
            }

            selectedDashboard = dashboard
            dashboardTitle = dashboard.title
            statusMessage = "Loading widgets"

            let resolvedWidgets = try await dashboardManager.widgets(forDashboard: dashboard.providerDashboardID)
            widgets = resolvedWidgets

            if resolvedWidgets.isEmpty {
                renderingState = .unavailable
                statusMessage = "This dashboard has no widgets to display."
                canRetry = true
            } else {
                renderingState = .ready
                statusMessage = ""
            }
        } catch {
            renderingState = .unavailable
            statusMessage = error.localizedDescription
            canRetry = true
        }
    }

    /// Ends the active Zabbix session.
    func disconnect() async {
        do {
            try await zabbixSessionService.disconnect()
            statusMessage = "Disconnected"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    /// Selects a specific dashboard to display, overriding automatic default selection.
    func selectDashboard(_ dashboard: Dashboard) {
        explicitDashboard = dashboard
        resetState()
    }

    /// Clears any explicit dashboard selection and resets to automatic default selection.
    func resetConnectionAttempt() {
        explicitDashboard = nil
        resetState()
    }

    /// Retries the current connection attempt without changing the selected dashboard.
    func retry() {
        resetState()
    }

    private func resetState() {
        hasPrepared = false
        renderingState = .idle
        statusMessage = "Preparing dashboard"
        selectedDashboard = nil
        widgets = []
        canRetry = false
    }

    private func resolveDashboard() async throws -> Dashboard? {
        if let explicitDashboard {
            return explicitDashboard
        }

        let dashboards = try await dashboardManager.dashboards(for: .zabbix)
        return dashboards.first(where: \.isDefault) ?? dashboards.first
    }
}
