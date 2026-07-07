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
    private var hasLoaded = false

    /// Creates a dashboard list view model.
    init(dashboardManager: DashboardManager) {
        self.dashboardManager = dashboardManager
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
}
