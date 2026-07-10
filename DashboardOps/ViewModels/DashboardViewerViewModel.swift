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

    /// All of the selected dashboard's pages, each with its own widgets and rotation duration.
    @Published private(set) var pages: [RenderableDashboardPage] = []

    /// Index into `pages` of the page currently on screen.
    @Published private(set) var currentPageIndex = 0

    /// Widgets for the page currently on screen.
    var widgets: [RenderableDashboardWidget] {
        pages.indices.contains(currentPageIndex) ? pages[currentPageIndex].widgets : []
    }

    /// Identifier of the page currently on screen, stable across refresh ticks — used to key a
    /// transition so rotating to a new page crossfades rather than cutting instantly.
    var currentPageID: String {
        pages.indices.contains(currentPageIndex) ? pages[currentPageIndex].id : "none"
    }

    /// How often the refresh loop checks which widgets are due, independent of any single
    /// widget's own interval — finer-grained than Zabbix's smallest widget refresh option (10s).
    private static let refreshTickNanoseconds: UInt64 = 5 * 1_000_000_000

    /// Backoff delays between automatic startup retry attempts, in seconds. The last value
    /// repeats for any further attempts.
    private static let startupRetryDelaysSeconds = [5, 15, 30, 60]

    /// Retry delay used once Zabbix itself has rejected a request (bad credentials, a disabled
    /// account, revoked permissions) rather than the request simply failing to reach it. Those
    /// don't self-heal on their own — only a human fixing the account will — so hammering the
    /// login endpoint every 60 seconds forever is pointless. Still fully automatic: whoever fixes
    /// the account doesn't need to touch the Apple TV, it just recovers within half an hour.
    private static let credentialFailureRetryDelaySeconds = 30 * 60

    private let dashboardManager: DashboardManager
    private let zabbixSessionService: ZabbixSessionService
    private var hasPrepared = false
    private var explicitDashboard: Dashboard?
    private var lastRefreshedAt: [String: Date] = [:]
    private var lastCredentialFailureAt: Date?
    private var refreshTask: Task<Void, Never>?
    private var backoffSleepTask: Task<Void, Never>?
    private var prepareTask: Task<Void, Never>?
    private var pageRotationTask: Task<Void, Never>?

    /// Whether the dashboard itself is configured to auto-rotate its pages, matching Zabbix's own
    /// "Start slideshow automatically" setting.
    private var autoRotatesPages = false

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
            guard let failure = await attemptLoad() else { return }
            guard !Task.isCancelled else { return }

            let delaySeconds = Self.retryDelaySeconds(forAttempt: attempt, after: failure)
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

    /// Chooses the next retry delay based on what kind of failure just happened. A `ZabbixAPIError`
    /// means the server was reached and responded — it rejected the login/request itself (bad
    /// credentials, disabled account, revoked permissions), which a faster retry won't fix. Any
    /// other error (network unreachable, DNS not resolved yet at boot, timeout) is treated as
    /// transient and keeps the normal fast backoff.
    private static func retryDelaySeconds(forAttempt attempt: Int, after failure: LoadFailure) -> Int {
        if failure.isServerRejection {
            return credentialFailureRetryDelaySeconds
        }
        return startupRetryDelaysSeconds[min(attempt, startupRetryDelaysSeconds.count - 1)]
    }

    /// A failed connect-and-load attempt, tagged with whether Zabbix itself rejected the request.
    private struct LoadFailure {
        let isServerRejection: Bool
    }

    /// Attempts one connect-and-load cycle. Returns `nil` on success, or a `LoadFailure` describing
    /// what went wrong.
    private func attemptLoad() async -> LoadFailure? {
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
                return LoadFailure(isServerRejection: false)
            }

            selectedDashboard = dashboard
            dashboardTitle = dashboard.title
            statusMessage = "Loading widgets"

            let resolvedDashboard = try await dashboardManager.renderableDashboard(forDashboardID: dashboard.providerDashboardID)
            pages = resolvedDashboard.pages
            currentPageIndex = 0
            autoRotatesPages = resolvedDashboard.autoRotatesPages

            let allWidgets = resolvedDashboard.pages.flatMap(\.widgets)
            if allWidgets.isEmpty {
                renderingState = .unavailable
                statusMessage = "This dashboard has no widgets to display."
                canRetry = true
                return LoadFailure(isServerRejection: false)
            }

            renderingState = .ready
            statusMessage = ""

            let now = Date()
            for widget in allWidgets {
                lastRefreshedAt[widget.id] = now
            }
            startRefreshLoop(dashboardID: dashboard.providerDashboardID)
            startPageRotationLoopIfNeeded()
            return nil
        } catch {
            renderingState = .unavailable
            statusMessage = error.localizedDescription
            canRetry = true
            return LoadFailure(isServerRejection: error is ZabbixAPIError)
        }
    }

    /// Ends the active Zabbix session.
    func disconnect() async {
        stopRefreshLoop()
        stopPageRotationLoop()

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
        stopPageRotationLoop()
        hasPrepared = false
        renderingState = .idle
        statusMessage = "Preparing dashboard"
        selectedDashboard = nil
        pages = []
        currentPageIndex = 0
        autoRotatesPages = false
        lastRefreshedAt.removeAll()
        lastCredentialFailureAt = nil
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
        // Checked across every page, not just the one currently on screen, so a page's data is
        // already fresh by the time rotation brings it into view instead of refreshing on a
        // delay after becoming visible.
        let allWidgets = pages.flatMap(\.widgets)
        let dueWidgetIDs = Set(
            allWidgets.compactMap { widget -> String? in
                guard let interval = widget.refreshIntervalSeconds else { return nil }
                let lastRefresh = lastRefreshedAt[widget.id] ?? .distantPast
                return now.timeIntervalSince(lastRefresh) >= TimeInterval(interval) ? widget.id : nil
            }
        )

        guard !dueWidgetIDs.isEmpty else { return }

        do {
            let updatedWidgets = try await dashboardManager.refreshWidgets(dueWidgetIDs, forDashboard: dashboardID)
            guard !updatedWidgets.isEmpty else { return }

            lastCredentialFailureAt = nil
            for widget in updatedWidgets {
                lastRefreshedAt[widget.id] = now
            }

            let updatedByID = Dictionary(uniqueKeysWithValues: updatedWidgets.map { ($0.id, $0) })
            pages = pages.map { page in
                RenderableDashboardPage(
                    id: page.id,
                    name: page.name,
                    widgets: page.widgets.map { updatedByID[$0.id] ?? $0 },
                    displaySeconds: page.displaySeconds
                )
            }
        } catch {
            // A dashboard that's already on screen shouldn't flash an error over a transient
            // network blip or an expired session — reconnect quietly and let the next tick retry.
            //
            // But if Zabbix itself rejected the request (the account was disabled or its password
            // changed mid-session, say), reconnecting will keep failing the same way every tick —
            // as often as every 5-30s depending on which widgets are due. That's the same "don't
            // hammer a failure only a human can fix" case as the startup path, just reachable after
            // the dashboard was already showing, so it gets the same slow-down treatment.
            if error is ZabbixAPIError {
                let now = Date()
                if let last = lastCredentialFailureAt, now.timeIntervalSince(last) < TimeInterval(Self.credentialFailureRetryDelaySeconds) {
                    return
                }
                lastCredentialFailureAt = now
            }

            _ = try? await zabbixSessionService.connect()
        }
    }

    // MARK: - Page rotation

    /// Starts auto-rotating through the dashboard's pages, mirroring Zabbix's own kiosk/slideshow
    /// mode: each page stays on screen for its own configured duration (or the dashboard's
    /// default) before advancing, looping back to the first page after the last. Only runs when
    /// the dashboard itself has more than one page and is configured to auto-rotate — a single
    /// page, or "auto_start" off, just stays put, matching what Zabbix's own frontend would show.
    private func startPageRotationLoopIfNeeded() {
        pageRotationTask?.cancel()
        pageRotationTask = nil

        guard autoRotatesPages, pages.count > 1 else { return }

        pageRotationTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let displaySeconds = self.pages.indices.contains(self.currentPageIndex)
                    ? self.pages[self.currentPageIndex].displaySeconds
                    : 30
                try? await Task.sleep(nanoseconds: UInt64(displaySeconds) * 1_000_000_000)
                guard !Task.isCancelled else { return }
                self.advanceToNextPage()
            }
        }
    }

    private func stopPageRotationLoop() {
        pageRotationTask?.cancel()
        pageRotationTask = nil
    }

    private func advanceToNextPage() {
        guard !pages.isEmpty else { return }
        currentPageIndex = (currentPageIndex + 1) % pages.count
    }
}
