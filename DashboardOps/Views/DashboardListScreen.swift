//
//  DashboardListScreen.swift
//  DashboardOps
//
//  Created by Codex on 7/7/26.
//

import SwiftUI

/// Placeholder screen for provider dashboards.
struct DashboardListScreen: View {
    /// Screen view model.
    @ObservedObject var viewModel: DashboardListViewModel

    /// Opens the selected dashboard.
    let onOpenDashboard: (Dashboard) -> Void

    /// Opens server configuration, for reconfiguring the connection later.
    let onOpenServerConfiguration: () -> Void

    var body: some View {
        ScreenScaffold(
            title: "Dashboards",
            subtitle: "Zabbix"
        ) {
            VStack(alignment: .leading, spacing: 24) {
                dashboardList

                Button("Server Configuration", action: onOpenServerConfiguration)
                    .buttonStyle(.bordered)
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
            }
        }
    }

    @ViewBuilder
    private var dashboardList: some View {
        Group {
            if viewModel.isLoading {
                ProgressView()
                    .controlSize(.large)
                    .tint(DashboardTheme.accent)
            } else if let errorMessage = viewModel.errorMessage {
                DashboardCard {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Dashboards Unavailable")
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .foregroundStyle(DashboardTheme.primaryText)

                        Text(errorMessage)
                            .font(.system(size: 24, weight: .regular, design: .rounded))
                            .foregroundStyle(DashboardTheme.secondaryText)
                    }
                }
            } else if viewModel.dashboards.isEmpty {
                DashboardCard {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("No Dashboards Found")
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .foregroundStyle(DashboardTheme.primaryText)

                        Text("This Zabbix server has no dashboards to display.")
                            .font(.system(size: 24, weight: .regular, design: .rounded))
                            .foregroundStyle(DashboardTheme.secondaryText)
                    }
                }
            } else {
                ScrollView {
                    VStack(spacing: 18) {
                        ForEach(viewModel.dashboards) { dashboard in
                            HStack(spacing: 16) {
                                Button(action: { onOpenDashboard(dashboard) }) {
                                    DashboardCard {
                                        VStack(alignment: .leading, spacing: 10) {
                                            HStack(spacing: 10) {
                                                Text(dashboard.title)
                                                    .font(.system(size: 30, weight: .bold, design: .rounded))
                                                    .foregroundStyle(DashboardTheme.primaryText)

                                                if dashboard.isDefault {
                                                    Text("Default")
                                                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                                                        .foregroundStyle(DashboardTheme.accent)
                                                        .padding(.horizontal, 10)
                                                        .padding(.vertical, 4)
                                                        .background(DashboardTheme.accent.opacity(0.18))
                                                        .clipShape(Capsule())
                                                }
                                            }

                                            if let subtitle = dashboard.subtitle {
                                                Text(subtitle)
                                                    .font(.system(size: 22, weight: .regular, design: .rounded))
                                                    .foregroundStyle(DashboardTheme.secondaryText)
                                            }
                                        }
                                    }
                                }
                                .buttonStyle(.plain)

                                if !dashboard.isDefault {
                                    Button("Set Default") {
                                        Task {
                                            await viewModel.setDefaultDashboard(dashboard)
                                        }
                                    }
                                    .buttonStyle(.bordered)
                                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                                }
                            }
                        }
                    }
                }
            }
        }
        .task {
            await viewModel.loadDashboards()
        }
    }
}
