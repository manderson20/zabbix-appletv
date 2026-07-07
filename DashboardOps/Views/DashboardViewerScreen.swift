//
//  DashboardViewerScreen.swift
//  DashboardOps
//
//  Created by Codex on 7/7/26.
//

import SwiftUI

/// Full-screen dashboard viewer.
///
/// tvOS has no WebKit/WKWebView, so a Zabbix dashboard's widgets are fetched via the API and
/// rendered natively (see `DashboardWidgetGridView`) rather than embedding the web frontend.
struct DashboardViewerScreen: View {
    /// Screen view model.
    @ObservedObject var viewModel: DashboardViewerViewModel

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            DashboardTheme.background.ignoresSafeArea()

            if viewModel.renderingState == .ready {
                DashboardWidgetGridView(widgets: viewModel.widgets)
                    .padding(24)
            }

            if viewModel.renderingState != .ready {
                VStack(alignment: .leading, spacing: 18) {
                    Text(viewModel.dashboardTitle)
                        .font(.system(size: 54, weight: .bold, design: .rounded))
                        .foregroundStyle(DashboardTheme.primaryText)

                    Text(viewModel.statusMessage)
                        .font(.system(size: 28, weight: .regular, design: .rounded))
                        .foregroundStyle(DashboardTheme.secondaryText)

                    if viewModel.renderingState == .loading {
                        ProgressView()
                            .controlSize(.large)
                            .tint(DashboardTheme.accent)
                            .padding(.top, 8)
                    }

                    if viewModel.canRetry {
                        Button("Retry") {
                            viewModel.retry()
                            Task {
                                await viewModel.prepareViewer()
                            }
                        }
                        .buttonStyle(.bordered)
                        .font(.system(size: 26, weight: .semibold, design: .rounded))
                        .padding(.top, 14)
                    }
                }
                .padding(.horizontal, DashboardTheme.horizontalScreenPadding)
                .padding(.bottom, DashboardTheme.verticalScreenPadding)
            }
        }
        .task {
            await viewModel.prepareViewer()
        }
        .toolbar(.hidden, for: .navigationBar)
        .persistentSystemOverlays(.hidden)
    }
}
