//
//  DashboardViewerViewModel.swift
//  DashboardOps
//
//  Created by Codex on 7/7/26.
//

import Combine
import Foundation

/// View model for the full-screen dashboard viewer.
@MainActor
final class DashboardViewerViewModel: ObservableObject {
    /// Dashboard title shown above the rendered dashboard.
    @Published private(set) var dashboardTitle = "Zabbix Dashboard"

    /// Current dashboard rendering state.
    @Published private(set) var renderingState: DashboardRenderingState = .idle

    /// Status message shown while the dashboard is not yet ready.
    @Published private(set) var statusMessage = "Preparing dashboard"

    /// Indicates whether the current connection attempt can be retried.
    @Published private(set) var canRetry = false

    /// Dashboard resolved for display.
    @Published private(set) var selectedDashboard: Dashboard?

    /// Widgets resolved for the selected dashboard's first page.
    @Published private(set) var widgets: [RenderableDashboardWidget] = []

    /// How often the refresh loop checks which widgets are due, independent of any single
    /// widget's own interval — finer-grained than Zabbix's smallest widget refresh option (10s).
    private static let refreshTickNanoseconds: UInt64 = 5 * 1_000_000_000

    /// Backoff delays between automatic startup retry attempts, in seconds. The last value
    /// repeats for any further attempts.
    private static let startupRetryDelaysSeconds = [5, 15, 30, 60]

    private let dashboardManager: DashboardManager
    private let zabbixSessionService: ZabbixSessionService
    private var hasPrepared = false
    private var explicitDashboard: Dashboard?
    private var lastRefreshedAt: [String: Date] = [:]
    private var refreshTask: Task<Void, Never>?
    private var backoffSleepTask: Task<Void, Never>?
    private var prepareTask: Task<Void, Never>?

    /// Creates a dashboard viewer view model.
    init(dashboardManager: DashboardManager, zabbixSessionService: ZabbixSessionService) {
        self.dashboardManager = dashboardManager
        self.zabbixSessionService = zabbixSessionService
    }

    /// Prepares the viewer by connecting to Zabbix and resolving a dashboard to display.
    ///
    /// On failure, keeps retrying automatically with backoff rather than stopping after one
    /// attempt — a wall-mounted display that only recovers via someone walking up with the Siri
    /// Remote defeats "no user interaction required during normal operation." The `Retry` button
    /// remains available to skip the current wait rather than as the only way to recover.
    ///
    /// The retry loop runs in its own explicitly-owned `Task` (rather than directly in this
    /// `async` function's body) so `resetState()` can reliably cancel an in-flight loop — e.g. if
    /// the user picks a different dashboard while a prior connection attempt is still retrying —
    /// without racing a fresh call to `prepareViewer()` against a stale one still running.
    func prepareViewer() async {
        guard !hasPrepared else { return }
        hasPrepared = true

        let task = Task { [weak self] in
            guard let self else { return }
            await self.runPrepareLoop()
        }
        prepareTask = task
        await task.value
    }

    private func runPrepareLoop() async {
        var attempt = 0
        while !Task.isCancelled {
            let succeeded = await attemptLoad()
            if succeeded || Task.isCancelled { return }

            let delaySeconds = Self.startupRetryDelaysSeconds[min(attempt, Self.startupRetryDelaysSeconds.count - 1)]
            attempt += 1
            statusMessage += " Retrying in \(delaySeconds)s\u{2026}"

            let sleepTask = Task {
                try? await Task.sleep(nanoseconds: UInt64(delaySeconds) * 1_000_000_000)
                return
            }
            backoffSleepTask = sleepTask
            await sleepTask.value
        }
    }

    /// Attempts one connect-and-load cycle. Returns whether it succeeded.
    private func attemptLoad() async -> Bool {
        renderingState = .loading
        statusMessage = "Connecting to Zabbix"
        canRetry = false

        do {
            let session = try await zabbixSessionService.connect()
            let versionText = session.serverVersion.map { "Zabbix \($0)" } ?? "Zabbix"

            guard let dashboard = try await resolveDashboard() else {
                dashboardTitle = "\(versionText) Dashboard"
                renderingState = .unavailable
                statusMessage = "No dashboards are available for this Zabbix server."
                canRetry = true
                return false
            }

            selectedDashboard = dashboard
            dashboardTitle = dashboard.title
            statusMessage = "Loading widgets"

            let resolvedWidgets = try await dashboardManager.widgets(forDashboard: dashboard.providerDashboardID)
            widgets = resolvedWidgets

            if resolvedWidgets.isEmpty {
                renderingState = .unavailable
                statusMessage = "This dashboard has no widgets to display."
                canRetry = true
                return false
            }

            renderingState = .ready
            statusMessage = ""

            let now = Date()
            for widget in resolvedWidgets {
                lastRefreshedAt[widget.id] = now
            }
            startRefreshLoop(dashboardID: dashboard.providerDashboardID)
            return true
        } catch {
            renderingState = .unavailable
            statusMessage = error.localizedDescription
            canRetry = true
            return false
        }
    }

    /// Ends the active Zabbix session.
    func disconnect() async {
        stopRefreshLoop()

        do {
            try await zabbixSessionService.disconnect()
            statusMessage = "Disconnected"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    /// Selects a specific dashboard to display, overriding automatic default selection.
    func selectDashboard(_ dashboard: Dashboard) {
        explicitDashboard = dashboard
        resetState()
    }

    /// Clears any explicit dashboard selection and resets to automatic default selection.
    func resetConnectionAttempt() {
        explicitDashboard = nil
        resetState()
    }

    /// Skips the remaining automatic backoff wait and retries immediately, without changing the
    /// selected dashboard. The `prepareViewer()` loop is already running and asleep whenever this
    /// is reachable (the Retry button only shows during a failure, i.e. mid-backoff), so this just
    /// wakes it — it does not start a second, competing attempt loop.
    func retry() {
        backoffSleepTask?.cancel()
    }

    private func resetState() {
        prepareTask?.cancel()
        prepareTask = nil
        backoffSleepTask?.cancel()
        backoffSleepTask = nil
        stopRefreshLoop()
        hasPrepared = false
        renderingState = .idle
        statusMessage = "Preparing dashboard"
        selectedDashboard = nil
        widgets = []
        lastRefreshedAt.removeAll()
        canRetry = false
    }

    private func resolveDashboard() async throws -> Dashboard? {
        if let explicitDashboard {
            return explicitDashboard
        }

        let dashboards = try await dashboardManager.dashboards(for: .zabbix)
        return dashboards.first(where: \.isDefault) ?? dashboards.first
    }

    // MARK: - Per-widget refresh

    /// Starts a loop that periodically re-resolves whichever widgets are due, based on each
    /// widget's own Zabbix-configured refresh interval, so a wall-mounted dashboard keeps showing
    /// live data instead of a single static snapshot from when the viewer opened.
    private func startRefreshLoop(dashboardID: String) {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: Self.refreshTickNanoseconds)
                guard !Task.isCancelled else { break }
                await self?.performRefreshTick(dashboardID: dashboardID)
            }
        }
    }

    private func stopRefreshLoop() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    private func performRefreshTick(dashboardID: String) async {
        let now = Date()
        let dueWidgetIDs = Set(
            widgets.compactMap { widget -> String? in
                guard let interval = widget.refreshIntervalSeconds else { return nil }
                let lastRefresh = lastRefreshedAt[widget.id] ?? .distantPast
                return now.timeIntervalSince(lastRefresh) >= TimeInterval(interval) ? widget.id : nil
            }
        )

        guard !dueWidgetIDs.isEmpty else { return }

        do {
            let updatedWidgets = try await dashboardManager.refreshWidgets(dueWidgetIDs, forDashboard: dashboardID)
            guard !updatedWidgets.isEmpty else { return }

            for widget in updatedWidgets {
                lastRefreshedAt[widget.id] = now
            }

            let updatedByID = Dictionary(uniqueKeysWithValues: updatedWidgets.map { ($0.id, $0) })
            widgets = widgets.map { updatedByID[$0.id] ?? $0 }
        } catch {
            // A dashboard that's already on screen shouldn't flash an error over a transient
            // network blip or an expired session — reconnect quietly and let the next tick retry.
            _ = try? await zabbixSessionService.connect()
        }
    }
}
