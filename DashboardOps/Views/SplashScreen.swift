//
//  SplashScreen.swift
//  DashboardOps
//
//  Created by Codex on 7/7/26.
//

import SwiftUI

/// Launch screen for DashboardOps.
struct SplashScreen: View {
    /// Screen view model.
    @ObservedObject var viewModel: SplashViewModel

    /// Opens server configuration.
    let onOpenServerConfiguration: () -> Void

    /// Opens the dashboard list.
    let onOpenDashboardList: () -> Void

    /// Opens the About screen.
    let onOpenAbout: () -> Void

    var body: some View {
        ScreenScaffold(
            title: "DashboardOps",
            subtitle: "Managed Apple TV dashboard display"
        ) {
            HStack(alignment: .top, spacing: 32) {
                DashboardCard {
                    VStack(alignment: .leading, spacing: 24) {
                        Image(systemName: "rectangle.on.rectangle")
                            .font(.system(size: 72, weight: .semibold))
                            .foregroundStyle(DashboardTheme.accent)

                        Text(viewModel.statusMessage)
                            .font(.system(size: 36, weight: .semibold, design: .rounded))
                            .foregroundStyle(DashboardTheme.primaryText)

                        if viewModel.isPreparing {
                            ProgressView()
                                .controlSize(.large)
                                .tint(DashboardTheme.accent)
                        }
                    }
                    .frame(minHeight: 250, alignment: .topLeading)
                }

                VStack(alignment: .leading, spacing: 18) {
                    Button("Server Configuration", action: onOpenServerConfiguration)
                        .buttonStyle(.borderedProminent)

                    Button("Dashboard List", action: onOpenDashboardList)
                        .buttonStyle(.bordered)

                    Button("About", action: onOpenAbout)
                        .buttonStyle(.bordered)
                }
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .focusSection()
            }
        }
    }
}
