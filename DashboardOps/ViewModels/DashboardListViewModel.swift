//
//  DashboardListViewModel.swift
//  DashboardOps
//
//  Created by Codex on 7/7/26.
//

import Combine
import Foundation

/// View model for the dashboard list screen.
@MainActor
final class DashboardListViewModel: ObservableObject {
    /// Dashboards returned by the selected provider.
    @Published private(set) var dashboards: [Dashboard] = []

    /// Indicates whether the list is loading.
    @Published private(set) var isLoading = false

    /// Error message shown when dashboards could not be loaded.
    @Published private(set) var errorMessage: String?

    private let dashboardManager: DashboardManager
    private let settingsService: SettingsService
    private var hasLoaded = false

    /// Creates a dashboard list view model.
    init(dashboardManager: DashboardManager, settingsService: SettingsService) {
        self.dashboardManager = dashboardManager
        self.settingsService = settingsService
    }

    /// Loads the dashboard list from the active provider.
    func loadDashboards() async {
        guard !hasLoaded else { return }
        hasLoaded = true
        isLoading = true
        defer { isLoading = false }

        do {
            dashboards = try await dashboardManager.dashboards(for: .zabbix)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Marks a dashboard as the default shown on launch, persisting the choice to the server
    /// configuration.
    func setDefaultDashboard(_ dashboard: Dashboard) async {
        guard var configuration = try? await settingsService.loadServerConfiguration() else {
            return
        }

        configuration.preferredDashboardID = dashboard.id
        try? await settingsService.saveServerConfiguration(configuration)

        dashboards = dashboards.map { existing in
            var updated = existing
            updated.isDefault = existing.id == dashboard.id
            return updated
        }
    }
}
