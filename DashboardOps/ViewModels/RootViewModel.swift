//
//  RootViewModel.swift
//  DashboardOps
//
//  Created by Codex on 7/7/26.
//

import Combine
import Foundation

/// Coordinates top-level navigation and screen view models.
@MainActor
final class RootViewModel: ObservableObject {
    /// Active navigation path.
    @Published var path: [AppRoute] = []

    /// Splash screen view model.
    let splashViewModel: SplashViewModel

    /// Settings screen view model.
    let settingsViewModel: SettingsViewModel

    /// Server configuration screen view model.
    let serverConfigurationViewModel: ServerConfigurationViewModel

    /// Dashboard list screen view model.
    let dashboardListViewModel: DashboardListViewModel

    /// Dashboard viewer screen view model.
    let dashboardViewerViewModel: DashboardViewerViewModel

    /// About screen view model.
    let aboutViewModel: AboutViewModel

    private let environment: AppEnvironment
    private var hasPreparedLaunch = false

    /// Creates the root view model with app dependencies.
    init(environment: AppEnvironment) {
        self.environment = environment
        splashViewModel = SplashViewModel()
        settingsViewModel = SettingsViewModel(providerRegistry: environment.providerRegistry)
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
        aboutViewModel = AboutViewModel()
    }

    /// Performs startup routing.
    func prepareLaunch() async {
        guard !hasPreparedLaunch else { return }
        hasPreparedLaunch = true

        await splashViewModel.prepareLaunch()
        let configuration = try? await environment.settingsService.loadServerConfiguration()
        path = configuration == nil ? [.settings] : [.dashboardViewer]
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

    /// Called after server configuration is saved. Routes to the dashboard list rather than
    /// straight into a dashboard, so the choice of which dashboard to show is an explicit one
    /// (this app has no other moment where that decision gets made) instead of silently landing
    /// on whichever dashboard Zabbix happens to return first.
    func completeServerConfiguration() {
        Task {
            await environment.zabbixSessionService.clearSession()
        }
        dashboardListViewModel.resetForNewConfiguration()
        dashboardViewerViewModel.resetConnectionAttempt()
        path = [.dashboardList]
    }

    /// Replaces the current path with one route.
    func replace(with route: AppRoute) {
        if route == .dashboardViewer {
            dashboardViewerViewModel.resetConnectionAttempt()
        }

        path = [route]
    }
}
