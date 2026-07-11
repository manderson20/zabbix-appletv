//
//  ContentView.swift
//  ZabbixAppleTVDashboard
//
//  Created by Mathew Anderson on 7/7/26.
//

import SwiftUI

/// Root SwiftUI view for Zabbix AppleTV Dashboard.
struct ContentView: View {
    @StateObject private var viewModel: RootViewModel

    /// Creates the root view with an app environment.
    init(environment: AppEnvironment = AppEnvironment()) {
        _viewModel = StateObject(wrappedValue: RootViewModel(environment: environment))
    }

    var body: some View {
        NavigationStack(path: $viewModel.path) {
            root
                .navigationDestination(for: AppRoute.self) { route in
                    destination(for: route)
                }
        }
        .tint(DashboardTheme.accent)
    }

    /// The stack's root screen — Server Configuration until one is saved, Dashboard List from
    /// then on. Not a pushed `AppRoute`: switching this swaps the root itself rather than stacking
    /// on top of it, so completing configuration for the first time replaces the root outright.
    @ViewBuilder
    private var root: some View {
        if viewModel.hasConfiguration {
            DashboardListScreen(
                viewModel: viewModel.dashboardListViewModel,
                onOpenDashboard: { dashboard in
                    viewModel.openDashboard(dashboard)
                },
                onOpenServerConfiguration: {
                    viewModel.navigate(to: .serverConfiguration)
                }
            )
        } else {
            ServerConfigurationScreen(
                viewModel: viewModel.serverConfigurationViewModel,
                onSaveComplete: {
                    viewModel.completeServerConfiguration()
                }
            )
        }
    }

    @ViewBuilder
    private func destination(for route: AppRoute) -> some View {
        switch route {
        case .serverConfiguration:
            ServerConfigurationScreen(
                viewModel: viewModel.serverConfigurationViewModel,
                onSaveComplete: {
                    viewModel.completeServerConfiguration()
                }
            )
        case .dashboardViewer:
            DashboardViewerScreen(viewModel: viewModel.dashboardViewerViewModel)
        }
    }
}
