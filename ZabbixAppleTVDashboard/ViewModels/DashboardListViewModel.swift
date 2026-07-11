//
//  DashboardListViewModel.swift
//  ZabbixAppleTVDashboard
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
    ///
    /// `hasLoaded` is only set once the attempt actually finishes — not before, and not when it's
    /// cancelled. This screen becomes the app's root right as server configuration completes (the
    /// root swaps from Server Configuration to Dashboard List in the same instant), and SwiftUI can
    /// recreate the view — restarting its `.task` — as part of that transition. A cancelled attempt
    /// isn't a real failure; surfacing it as one while also marking `hasLoaded` would permanently
    /// block any retry, since nothing else ever calls this again. Confirmed live: saving a valid
    /// server configuration landed on a permanent "cancelled" error that only a full app relaunch
    /// cleared, even though the exact same credentials connected fine on that relaunch.
    func loadDashboards() async {
        guard !hasLoaded else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            dashboards = try await dashboardManager.dashboards(for: .zabbix)
            hasLoaded = true
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
            hasLoaded = true
        }
    }

    /// Clears cached dashboards so the next `loadDashboards()` call refetches — used when the
    /// server configuration changes, since the previous list belonged to a different server.
    func resetForNewConfiguration() {
        hasLoaded = false
        dashboards = []
        errorMessage = nil
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
