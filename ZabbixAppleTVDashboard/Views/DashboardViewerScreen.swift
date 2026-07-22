//
//  DashboardViewerScreen.swift
//  ZabbixAppleTVDashboard
//
//  Created by Codex on 7/7/26.
//

import SwiftUI
import UIKit

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
                // Ignoring the safe area here too (not just on the background) matters: without
                // it, the system's own default tvOS safe-area inset was stacking on top of the
                // padding below, leaving a noticeably bigger edge margin than system screens like
                // the Home Screen or Settings use.
                //
                // Keying on the page id (rather than always reusing the same view identity) and
                // animating on that id crossfades between pages during auto-rotation, matching
                // Zabbix's own kiosk slideshow transition instead of cutting instantly.
                DashboardWidgetGridView(
                    widgets: viewModel.widgets,
                    autoScrollEnabled: viewModel.autoScrollEnabled,
                    onToggleAutoScroll: { viewModel.toggleAutoScroll() }
                )
                    .id(viewModel.currentPageID)
                    .transition(.opacity)
                    .padding(8)
                    .ignoresSafeArea()
                    .environment(\.dashboardAutoScrollEnabled, viewModel.autoScrollEnabled)
                    .animation(.easeInOut(duration: 0.6), value: viewModel.currentPageID)
            }

            // A quiet reminder, only while manual scrolling is on, that the page is under remote
            // control now (and how to move it) — auto-scroll, the default kiosk state, stays silent.
            if viewModel.renderingState == .ready, !viewModel.autoScrollEnabled {
                manualScrollIndicator
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(24)
                    .transition(.opacity)
            }

            // Surfaces only during a sustained outage while a dashboard is already on screen, so a
            // wall display shows its data may be stale rather than freezing silently. It disappears
            // the moment a refresh succeeds again — the viewer self-heals on its own.
            if viewModel.renderingState == .ready, viewModel.isReconnecting {
                reconnectingBanner
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(24)
                    .transition(.opacity)
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
                        Button("Retry Now") {
                            viewModel.retry()
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
        .animation(.easeInOut(duration: 0.3), value: viewModel.autoScrollEnabled)
        .animation(.easeInOut(duration: 0.3), value: viewModel.isReconnecting)
        .task {
            await viewModel.prepareViewer()
        }
        .toolbar(.hidden, for: .navigationBar)
        .persistentSystemOverlays(.hidden)
        .onAppear {
            // Keeps the Apple TV from going to its screensaver/sleep while the dashboard is on
            // screen — this app has no expected remote interaction during normal operation, so
            // tvOS's default idle behavior would otherwise defeat an always-on wall display.
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    /// Amber pill shown during a sustained connection outage, noting the data may be stale and
    /// when it was last updated. Purely informational — the viewer keeps reconnecting on its own.
    private var reconnectingBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "wifi.exclamationmark")
            Text(lastUpdatedText)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(
            Capsule(style: .continuous).fill(Color.orange.opacity(0.92))
        )
    }

    /// "Reconnecting — last updated 2:47 PM", or a bare fallback if no successful load happened yet
    /// (which the banner's `isReconnecting` gate makes unreachable in practice).
    private var lastUpdatedText: String {
        guard let at = viewModel.lastSuccessfulRefreshAt else { return "Reconnecting\u{2026}" }
        return "Reconnecting \u{2014} last updated \(at.formatted(date: .omitted, time: .shortened))"
    }

    /// The unobtrusive "you're scrolling by hand" pill shown in manual mode.
    private var manualScrollIndicator: some View {
        HStack(spacing: 10) {
            Image(systemName: "hand.draw")
            Text("Manual · swipe to scroll · Play/Pause to resume")
                .font(.system(size: 18, weight: .medium, design: .rounded))
        }
        .foregroundStyle(DashboardTheme.primaryText.opacity(0.85))
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(
            Capsule(style: .continuous)
                .fill(DashboardTheme.secondaryCardBackground.opacity(0.9))
        )
    }
}
