//
//  ContentView.swift
//  DashboardOps
//
//  Created by Mathew Anderson on 7/7/26.
//

import SwiftUI

/// Root SwiftUI view for DashboardOps.
struct ContentView: View {
    @StateObject private var viewModel: RootViewModel

    /// Creates the root view with an app environment.
    init(environment: AppEnvironment = AppEnvironment()) {
        _viewModel = StateObject(wrappedValue: RootViewModel(environment: environment))
    }

    var body: some View {
        NavigationStack(path: $viewModel.path) {
            SplashScreen(
                viewModel: viewModel.splashViewModel,
                onOpenSettings: {
                    viewModel.replace(with: .settings)
                },
                onOpenAbout: {
                    viewModel.navigate(to: .about)
                }
            )
            .navigationDestination(for: AppRoute.self) { route in
                destination(for: route)
            }
        }
        .tint(DashboardTheme.accent)
        .task {
            await viewModel.prepareLaunch()
        }
    }

    @ViewBuilder
    private func destination(for route: AppRoute) -> some View {
        switch route {
        case .settings:
            SettingsScreen(
                viewModel: viewModel.settingsViewModel,
                onOpenServerConfiguration: {
                    viewModel.navigate(to: .serverConfiguration)
                },
                onOpenDashboardList: {
                    viewModel.navigate(to: .dashboardList)
                },
                onOpenAbout: {
                    viewModel.navigate(to: .about)
                }
            )
        case .serverConfiguration:
            ServerConfigurationScreen(
                viewModel: viewModel.serverConfigurationViewModel,
                onSaveComplete: {
                    viewModel.completeServerConfiguration()
                }
            )
        case .dashboardList:
            DashboardListScreen(
                viewModel: viewModel.dashboardListViewModel,
                onOpenDashboard: { dashboard in
                    viewModel.openDashboard(dashboard)
                }
            )
        case .dashboardViewer:
            DashboardViewerScreen(viewModel: viewModel.dashboardViewerViewModel)
        case .about:
            AboutScreen(viewModel: viewModel.aboutViewModel)
        }
    }
}
