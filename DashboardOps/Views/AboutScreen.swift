//
//  AboutScreen.swift
//  DashboardOps
//
//  Created by Codex on 7/7/26.
//

import SwiftUI

/// About screen with product and version details.
struct AboutScreen: View {
    /// Screen view model.
    @ObservedObject var viewModel: AboutViewModel

    var body: some View {
        ScreenScaffold(
            title: "About",
            subtitle: viewModel.appName
        ) {
            VStack(alignment: .leading, spacing: 20) {
                DashboardCard {
                    VStack(alignment: .leading, spacing: 18) {
                        aboutRow(title: "Version", value: viewModel.version)
                        aboutRow(title: "Build", value: viewModel.buildNumber)
                        aboutRow(title: "Primary Provider", value: viewModel.primaryProvider)
                        aboutRow(title: "Distribution", value: "Apple School Manager and Mosyle MDM")
                    }
                }
            }
        }
    }

    private func aboutRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 24, weight: .medium, design: .rounded))
                .foregroundStyle(DashboardTheme.secondaryText)

            Spacer()

            Text(value)
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .foregroundStyle(DashboardTheme.primaryText)
        }
    }
}
