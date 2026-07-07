//
//  ServerConfigurationScreen.swift
//  DashboardOps
//
//  Created by Codex on 7/7/26.
//

import SwiftUI

/// Placeholder screen for Zabbix server configuration.
struct ServerConfigurationScreen: View {
    /// Screen view model.
    @ObservedObject var viewModel: ServerConfigurationViewModel

    /// Called after configuration saves successfully.
    let onSaveComplete: () -> Void

    var body: some View {
        ScreenScaffold(
            title: "Server Configuration",
            subtitle: "Zabbix connection settings"
        ) {
            VStack(alignment: .leading, spacing: 24) {
                DashboardCard {
                    VStack(alignment: .leading, spacing: 24) {
                        SettingsField(title: "Name", text: $viewModel.displayName)
                        SettingsField(title: "Server URL", text: $viewModel.serverURL)
                        SettingsField(title: "Username", text: $viewModel.username)
                        SecureSettingsField(title: "Password", text: $viewModel.password)

                        Toggle("Allow Self-Signed Certificates", isOn: $viewModel.allowsSelfSignedCertificates)
                            .font(.system(size: 24, weight: .medium, design: .rounded))
                            .foregroundStyle(DashboardTheme.primaryText)
                    }
                }

                HStack(spacing: 18) {
                    Button("Save", action: {
                        Task {
                            let didSave = await viewModel.save()
                            if didSave {
                                onSaveComplete()
                            }
                        }
                    })
                    .buttonStyle(.borderedProminent)
                    .disabled(!viewModel.canSave || viewModel.isSaving)

                    validationText
                }
                .font(.system(size: 26, weight: .semibold, design: .rounded))
            }
            .task {
                await viewModel.load()
            }
        }
    }

    @ViewBuilder
    private var validationText: some View {
        switch viewModel.validationState {
        case .idle:
            EmptyView()
        case .valid:
            Text(viewModel.statusMessage)
                .foregroundStyle(.green)
        case .invalid:
            Text(viewModel.statusMessage.isEmpty ? "Review Required" : viewModel.statusMessage)
                .foregroundStyle(.yellow)
        }
    }
}
