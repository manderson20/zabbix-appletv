//
//  DashboardViewerViewModel.swift
//  ZabbixAppleTVDashboard
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

    /// True when a dashboard is already on screen but refreshes have kept failing long enough
    /// (see `stalenessThresholdSeconds`) that the displayed data may be stale. Drives the
    /// reconnecting banner. Clears automatically on the next successful refresh — the viewer
    /// self-heals with no user action.
    @Published private(set) var isReconnecting = false

    /// Timestamp of the last successful data refresh (initial load or a refresh tick), shown as
    /// "last updated" in the reconnecting banner. Nil until the first successful load.
    @Published private(set) var lastSuccessfulRefreshAt: Date?

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
    /// At 2s, widgets on the app's fast lane (a widget left at Zabbix's 10s minimum — see
    /// `DashboardManager.refreshIntervalSeconds(from:)`) repaint within ~2s, beating the Zabbix
    /// web dashboard's hard 10s floor for near-real-time views like door status.
    private static let refreshTickNanoseconds: UInt64 = 2 * 1_000_000_000

    /// How long refreshes must keep failing, after a dashboard is already on screen, before the
    /// viewer surfaces the "reconnecting — data may be stale" banner. Kept well above a single
    /// refresh interval so a brief blip or one dropped tick never flashes a warning; a real outage
    /// crosses it and the banner appears, then disappears the instant a refresh succeeds again.
    private static let stalenessThresholdSeconds: TimeInterval = 30

    /// How often the dashboard's own layout — which pages exist, which widgets are on them, where
    /// they sit — is re-read, independent of any widget's data refresh. Editing a dashboard in
    /// Zabbix is a human-scale action on an unattended display, so a minute is prompt enough, and
    /// it keeps a dashboard of slow-refreshing widgets from issuing a `dashboard.get` every tick.
    private static let layoutRefreshIntervalSeconds: TimeInterval = 60

    /// Backoff delays between automatic startup retry attempts, in seconds. The last value
    /// repeats for any further attempts.
    private static let startupRetryDelaysSeconds = [5, 15, 30, 60]

    /// Retry delay used once Zabbix itself has rejected a *login* (bad credentials, a disabled
    /// account) rather than the request simply failing to reach it. Those don't self-heal on their
    /// own — only a human fixing the account will — so hammering the login endpoint every 60
    /// seconds forever is pointless. Still fully automatic: whoever fixes the account doesn't need
    /// to touch the Apple TV, it just recovers within half an hour.
    ///
    /// Deliberately keyed off the login attempt and nothing else. A *data* request coming back as a
    /// `ZabbixAPIError` looks identical to a rejected login but usually is not one — restarting
    /// Zabbix invalidates the auth token, so the next tick fails with "Not authorised: session
    /// terminated, re-login, please", which a single re-login fixes. Backing off half an hour for
    /// that would leave a wall display dark long after the server came back.
    static let credentialFailureRetryDelaySeconds = 30 * 60

    /// Whether a page taller than the screen auto-scrolls (default) or is scrolled by hand with the
    /// remote. Toggled live from the viewer and persisted, so a wall display keeps the chosen mode
    /// across restarts.
    @Published private(set) var autoScrollEnabled = true

    private let dashboardManager: DashboardManager
    private let zabbixSessionService: ZabbixSessionService
    private let settingsService: SettingsService
    private var hasPrepared = false
    private var explicitDashboard: Dashboard?
    private var lastRefreshedAt: [String: Date] = [:]
    private var lastLayoutRefreshAt: Date?
    private var lastCredentialFailureAt: Date?
    private var refreshTask: Task<Void, Never>?
    private var backoffSleepTask: Task<Void, Never>?
    private var prepareTask: Task<Void, Never>?
    private var pageRotationTask: Task<Void, Never>?

    /// Whether the dashboard itself is configured to auto-rotate its pages, matching Zabbix's own
    /// "Start slideshow automatically" setting.
    private var autoRotatesPages = false

    /// Creates a dashboard viewer view model.
    init(dashboardManager: DashboardManager, zabbixSessionService: ZabbixSessionService, settingsService: SettingsService) {
        self.dashboardManager = dashboardManager
        self.zabbixSessionService = zabbixSessionService
        self.settingsService = settingsService
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

        // Restore the saved scroll mode before the first frame, so a display configured for manual
        // scrolling doesn't briefly auto-scroll on launch.
        if let settings = try? await settingsService.loadDisplaySettings() {
            autoScrollEnabled = settings.autoScrollEnabled
        }

        let task = Task { [weak self] in
            guard let self else { return }
            await self.runPrepareLoop()
        }
        prepareTask = task
        await task.value
    }

    /// Flips between auto-scroll and manual (remote-driven) scrolling, persisting the choice so it
    /// survives a restart. Bound to the remote's Play/Pause button in the viewer.
    func toggleAutoScroll() {
        autoScrollEnabled.toggle()
        let enabled = autoScrollEnabled
        Task { [weak self] in
            guard let self else { return }
            var settings = (try? await self.settingsService.loadDisplaySettings()) ?? .standard
            settings.autoScrollEnabled = enabled
            try? await self.settingsService.saveDisplaySettings(settings)
        }
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

    /// Chooses the next retry delay based on what kind of failure just happened. A rejected *login*
    /// means Zabbix was reached and turned the account away (bad credentials, disabled account),
    /// which a faster retry won't fix. Everything else — network unreachable, DNS not resolved yet
    /// at boot, timeout, or a data request that failed after a successful login — is treated as
    /// transient and keeps the normal fast backoff.
    static func retryDelaySeconds(forAttempt attempt: Int, after failure: LoadFailure) -> Int {
        if failure.isLoginRejection {
            return credentialFailureRetryDelaySeconds
        }
        return startupRetryDelaysSeconds[min(attempt, startupRetryDelaysSeconds.count - 1)]
    }

    /// A failed connect-and-load attempt, tagged with whether Zabbix itself rejected the login.
    ///
    /// Only a rejected login counts. A failure anywhere *after* the login succeeded (dashboard
    /// list, widget resolution) is transient as far as backoff is concerned — a permissions gap
    /// there is fixed server-side and should be picked up within a minute, not half an hour.
    struct LoadFailure {
        let isLoginRejection: Bool
    }

    /// Attempts one connect-and-load cycle. Returns `nil` on success, or a `LoadFailure` describing
    /// what went wrong.
    private func attemptLoad() async -> LoadFailure? {
        renderingState = .loading
        statusMessage = "Connecting to Zabbix"
        canRetry = false

        // The login is attempted on its own so a rejection here — the one failure a human has to
        // fix — is distinguishable from everything that can go wrong afterwards.
        let session: UserSession
        do {
            session = try await zabbixSessionService.connect()
        } catch {
            renderingState = .unavailable
            statusMessage = error.localizedDescription
            canRetry = true
            return LoadFailure(isLoginRejection: error is ZabbixAPIError)
        }

        do {
            let versionText = session.serverVersion.map { "Zabbix \($0)" } ?? "Zabbix"

            guard let dashboard = try await resolveDashboard() else {
                dashboardTitle = "\(versionText) Dashboard"
                renderingState = .unavailable
                statusMessage = "No dashboards are available for this Zabbix server."
                canRetry = true
                return LoadFailure(isLoginRejection: false)
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
                return LoadFailure(isLoginRejection: false)
            }

            renderingState = .ready
            statusMessage = ""

            let now = Date()
            for widget in allWidgets {
                lastRefreshedAt[widget.id] = now
            }
            lastSuccessfulRefreshAt = now
            lastLayoutRefreshAt = now
            isReconnecting = false
            startRefreshLoop(dashboardID: dashboard.providerDashboardID)
            startPageRotationLoopIfNeeded()
            return nil
        } catch {
            renderingState = .unavailable
            statusMessage = error.localizedDescription
            canRetry = true
            return LoadFailure(isLoginRejection: false)
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
        lastLayoutRefreshAt = nil
        lastCredentialFailureAt = nil
        canRetry = false
        isReconnecting = false
        lastSuccessfulRefreshAt = nil
    }

    private func resolveDashboard() async throws -> Dashboard? {
        if let explicitDashboard {
            return explicitDashboard
        }

        let dashboards = try await dashboardManager.dashboards(for: .zabbix)
        #if DEBUG
        if let target = dashboards.first(where: { $0.title.lowercased() == "qa" }) { return target }
        #endif
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
        let knownWidgetIDs = Set(allWidgets.map(\.id))
        let dueWidgetIDs = Set(
            allWidgets.compactMap { widget -> String? in
                let lastRefresh = lastRefreshedAt[widget.id] ?? .distantPast
                return now.timeIntervalSince(lastRefresh) >= TimeInterval(widget.refreshIntervalSeconds) ? widget.id : nil
            }
        )

        // The layout is re-read on its own slower cadence as well as whenever data is due, so a
        // widget added in Zabbix appears within a minute even on a dashboard whose widgets all
        // refresh slowly — without a `dashboard.get` on every 2s tick.
        let layoutIsDue = now.timeIntervalSince(lastLayoutRefreshAt ?? .distantPast) >= Self.layoutRefreshIntervalSeconds
        guard !dueWidgetIDs.isEmpty || layoutIsDue else { return }

        do {
            let refreshed = try await dashboardManager.refreshedDashboard(
                forDashboardID: dashboardID,
                dueWidgetIDs: dueWidgetIDs,
                knownWidgetIDs: knownWidgetIDs
            )

            lastCredentialFailureAt = nil
            lastSuccessfulRefreshAt = now
            lastLayoutRefreshAt = now
            isReconnecting = false
            apply(refreshed, at: now)
        } catch {
            // Once an outage is sustained (not a one-tick blip), surface a reconnecting hint so an
            // always-on wall display shows its data may be stale instead of silently freezing. This
            // only flips a flag for the banner — it doesn't gate the reconnect below, and the next
            // successful tick clears it.
            if let last = lastSuccessfulRefreshAt, Date().timeIntervalSince(last) >= Self.stalenessThresholdSeconds {
                isReconnecting = true
            }

            // A dashboard that's already on screen shouldn't flash an error over a transient
            // network blip or an expired session — reconnect quietly and let the next tick retry.
            await reconnectAfterFailedRefresh()
        }
    }

    /// Rebuilds the on-screen pages from the layout Zabbix just reported, carrying over already
    /// resolved data for the widgets that weren't re-fetched.
    ///
    /// The page and widget list is taken from the server rather than from what happens to be on
    /// screen, so widgets and whole pages added or deleted in Zabbix appear and disappear on their
    /// own. Widgets whose data wasn't due still pick up their current geometry and header settings,
    /// which cost nothing to read — a widget moved or resized in Zabbix follows immediately instead
    /// of waiting for its own refresh interval to come round.
    private func apply(_ refreshed: RefreshedDashboard, at now: Date) {
        let rebuiltPages = Self.mergedPages(from: refreshed, reusingDataFrom: pages)

        pages = rebuiltPages
        autoRotatesPages = refreshed.autoRotatesPages

        for widget in refreshed.pages.flatMap(\.widgets) where widget.resolved != nil {
            lastRefreshedAt[widget.id] = now
        }

        // Stop tracking refresh times for widgets that no longer exist, so a long-running display
        // doesn't accumulate an entry per widget ever deleted from the dashboard.
        let liveWidgetIDs = Set(rebuiltPages.flatMap(\.widgets).map(\.id))
        lastRefreshedAt = lastRefreshedAt.filter { liveWidgetIDs.contains($0.key) }

        // Pages may have been added or removed out from under the rotation.
        if !rebuiltPages.indices.contains(currentPageIndex) {
            currentPageIndex = 0
        }
        let shouldRotate = autoRotatesPages && rebuiltPages.count > 1
        if shouldRotate != (pageRotationTask != nil) {
            if shouldRotate {
                startPageRotationLoopIfNeeded()
            } else {
                stopPageRotationLoop()
            }
        }
    }

    /// Merges a freshly read layout with the widget data already on screen.
    ///
    /// Structure comes entirely from `refreshed` — the page list, their order, and which widgets
    /// sit on each — so adds and deletes on either level follow the server rather than persisting
    /// from whatever the viewer loaded at startup. `existingPages` contributes only the resolved
    /// rendering for widgets that weren't re-fetched this time.
    static func mergedPages(
        from refreshed: RefreshedDashboard,
        reusingDataFrom existingPages: [RenderableDashboardPage]
    ) -> [RenderableDashboardPage] {
        let existingByID = Dictionary(
            existingPages.flatMap(\.widgets).map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        return refreshed.pages.map { page in
            RenderableDashboardPage(
                id: page.id,
                name: page.name,
                widgets: page.widgets.compactMap { widget -> RenderableDashboardWidget? in
                    if let resolved = widget.resolved {
                        return resolved
                    }

                    // Not re-fetched, so reuse the rendering already on screen — but under the
                    // layout the server just reported, so a move or resize takes effect without
                    // waiting for this widget's own refresh interval to come round.
                    //
                    // A widget with neither fresh data nor existing data can't be drawn at all.
                    // Dropping it is unreachable in practice: anything the viewer hasn't seen is
                    // always resolved rather than left for this branch.
                    guard let existing = existingByID[widget.id] else { return nil }
                    return RenderableDashboardWidget(
                        id: existing.id,
                        title: widget.customTitle ?? existing.title,
                        frame: widget.frame,
                        refreshIntervalSeconds: widget.refreshIntervalSeconds,
                        hasHiddenHeader: widget.hasHiddenHeader,
                        kind: existing.kind
                    )
                },
                displaySeconds: page.displaySeconds
            )
        }
    }

    /// Re-establishes the Zabbix session after a refresh tick failed, whatever the reason.
    ///
    /// The reconnect is attempted for *every* failure rather than only for ones that don't look
    /// like a rejection, because the two are indistinguishable from the failing request alone: a
    /// server restart invalidates the auth token, so a perfectly healthy dashboard starts failing
    /// with a `ZabbixAPIError` that one re-login clears. Only the login's own verdict is trusted —
    /// if Zabbix rejects the credentials themselves, that needs a human and backs off hard; if the
    /// login merely fails to land (server still rebooting, network down), the next tick tries again
    /// seconds later.
    ///
    /// Refresh ticks keep running throughout the backoff, so a session that turns out to still be
    /// valid recovers on its own and clears the backoff without waiting it out.
    private func reconnectAfterFailedRefresh() async {
        if let last = lastCredentialFailureAt,
           Date().timeIntervalSince(last) < TimeInterval(Self.credentialFailureRetryDelaySeconds) {
            return
        }

        do {
            _ = try await zabbixSessionService.connect()
            lastCredentialFailureAt = nil
        } catch is ZabbixAPIError {
            // Zabbix answered and turned the login away — bad password, disabled account, revoked
            // access. Retrying every few seconds won't fix it, so slow down until someone does.
            lastCredentialFailureAt = Date()
        } catch {
            // Never reached Zabbix (server rebooting, network down, DNS not up yet). Transient by
            // definition — leave the backoff clear so the next tick retries immediately.
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
