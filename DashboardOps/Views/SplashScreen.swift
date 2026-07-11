//
//  SplashScreen.swift
//  DashboardOps
//
//  Created by Codex on 7/7/26.
//

import SwiftUI

/// Launch screen for DashboardOps — shown only for the brief moment it takes to check for a saved
/// server configuration, never a destination the user navigates back to. `RootViewModel` replaces
/// this with the actual destination (server configuration, or the dashboard list plus viewer)
/// as soon as that check completes, so there are no buttons here to navigate anywhere.
struct SplashScreen: View {
    /// Screen view model.
    @ObservedObject var viewModel: SplashViewModel

    var body: some View {
        ScreenScaffold(
            title: "DashboardOps",
            subtitle: "Managed Apple TV dashboard display"
        ) {
            DashboardCard {
                VStack(alignment: .leading, spacing: 24) {
                    Image(systemName: "rectangle.on.rectangle")
                        .font(.system(size: 72, weight: .semibold))
                        .foregroundStyle(DashboardTheme.accent)

                    Text(viewModel.statusMessage)
                        .font(.system(size: 36, weight: .semibold, design: .rounded))
                        .foregroundStyle(DashboardTheme.primaryText)

                    ProgressView()
                        .controlSize(.large)
                        .tint(DashboardTheme.accent)
                }
                .frame(minHeight: 250, alignment: .topLeading)
            }
        }
    }
}
