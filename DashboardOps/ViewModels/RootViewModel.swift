//
//  RootViewModel.swift
//  DashboardOps
//
//  Created by Codex on 7/7/26.
//

import Combine
import Foundation

/// Coordinates top-level navigation and screen view models.
///
/// The app has exactly two things that can act as its root screen — Server Configuration (nothing
/// saved yet) or Dashboard List (already configured) — selected by `hasConfiguration` rather than
/// pushed onto `path`. `path` only ever holds what's stacked on top of whichever root is current:
/// Dashboard Viewer (picked a dashboard) or Server Configuration again (editing it later from the
/// list). There's deliberately no loading/splash screen in between: `hasConfiguration` is known
/// synchronously at init, so the very first frame already shows the right root.
@MainActor
final class RootViewModel: ObservableObject {
    /// Whether a server is already configured — decides the root screen.
    @Published private(set) var hasConfiguration: Bool

    /// Destinations pushed on top of the current root screen.
    @Published var path: [AppRoute] = []

    /// Server configuration screen view model.
    let serverConfigurationViewModel: ServerConfigurationViewModel

    /// Dashboard list screen view model.
    let dashboardListViewModel: DashboardListViewModel

    /// Dashboard viewer screen view model.
    let dashboardViewerViewModel: DashboardViewerViewModel

    private let environment: AppEnvironment

    /// Creates the root view model with app dependencies.
    init(environment: AppEnvironment) {
        self.environment = environment
        hasConfiguration = environment.settingsService.hasServerConfiguration()
        serverConfigurationViewModel = ServerConfigurationViewModel(
            settingsService: environment.settingsService,
            keychainService: environment.keychainService
        )
        dashboardListViewModel = DashboardListViewModel(
            dashboardManager: environment.dashboardManager,
            settingsService: environment.settingsService
        )
        dashboardViewerViewModel = DashboardViewerViewModel(
            dashboardManager: environment.dashboardManager,
            zabbixSessionService: environment.zabbixSessionService
        )
    }

    /// Appends a route to the current navigation path.
    func navigate(to route: AppRoute) {
        path.append(route)
    }

    /// Opens a specific dashboard in the full-screen viewer, and remembers it as the default —
    /// on an unattended kiosk display there's no real notion of "just peek at this one," so
    /// picking a dashboard from the list is treated as the persistent choice, not a one-off.
    func openDashboard(_ dashboard: Dashboard) {
        Task {
            await dashboardListViewModel.setDefaultDashboard(dashboard)
        }
        dashboardViewerViewModel.selectDashboard(dashboard)
        navigate(to: .dashboardViewer)
    }

    /// Called after server configuration is saved, whether for the first time (root was Server
    /// Configuration) or edited later (root already Dashboard List, this was pushed on top of it)
    /// — either way, clearing `path` lands on the Dashboard List root, freshly reloaded for
    /// whatever server is now configured, rather than silently reusing the previous server's list.
    func completeServerConfiguration() {
        Task {
            await environment.zabbixSessionService.clearSession()
        }
        dashboardListViewModel.resetForNewConfiguration()
        dashboardViewerViewModel.resetConnectionAttempt()
        hasConfiguration = true
        path = []
    }
}
