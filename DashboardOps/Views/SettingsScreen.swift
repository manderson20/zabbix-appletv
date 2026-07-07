//
//  SettingsScreen.swift
//  DashboardOps
//
//  Created by Codex on 7/7/26.
//

import SwiftUI

/// Settings hub for provider configuration and app information.
struct SettingsScreen: View {
    /// Screen view model.
    @ObservedObject var viewModel: SettingsViewModel

    /// Opens server configuration.
    let onOpenServerConfiguration: () -> Void

    /// Opens dashboard list.
    let onOpenDashboardList: () -> Void

    /// Opens About.
    let onOpenAbout: () -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 20),
        GridItem(.flexible(), spacing: 20),
        GridItem(.flexible(), spacing: 20)
    ]

    var body: some View {
        ScreenScaffold(
            title: "Settings",
            subtitle: "Provider setup and display preferences"
        ) {
            VStack(alignment: .leading, spacing: 28) {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                    ForEach(viewModel.providers) { provider in
                        DashboardCard {
                            VStack(alignment: .leading, spacing: 18) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(provider.name)
                                        .font(.system(size: 30, weight: .bold, design: .rounded))
                                        .foregroundStyle(DashboardTheme.primaryText)

                                    Spacer()

                                    ProviderStatusBadge(status: provider.supportStatus)
                                }

                                Text(provider.isPrimary ? "Version 1" : "Future")
                                    .font(.system(size: 22, weight: .medium, design: .rounded))
                                    .foregroundStyle(DashboardTheme.secondaryText)
                            }
                        }
                        .opacity(provider.supportStatus == .supported ? 1 : 0.62)
                    }
                }

                HStack(spacing: 18) {
                    Button("Server Configuration", action: onOpenServerConfiguration)
                        .buttonStyle(.borderedProminent)

                    Button("Dashboard List", action: onOpenDashboardList)
                        .buttonStyle(.bordered)

                    Button("About", action: onOpenAbout)
                        .buttonStyle(.bordered)
                }
                .font(.system(size: 26, weight: .semibold, design: .rounded))
                .focusSection()
            }
        }
    }
}
