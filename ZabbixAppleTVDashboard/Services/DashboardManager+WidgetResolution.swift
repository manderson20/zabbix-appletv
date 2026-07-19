//
//  DashboardManager+WidgetResolution.swift
//  ZabbixAppleTVDashboard
//
//  Created by Codex on 7/7/26.
//

import Foundation

/// Resolves each Zabbix dashboard widget type into a `DashboardWidgetKind` with real data.
///
/// Widget geometry and simple filter fields (severities, host/group scoping) follow the
/// dot-indexed naming convention verified against a live Zabbix 7.0 server (e.g. "itemid.0",
/// "severities.0", "groupids.0"). Fields specific to a single widget type that weren't verified
/// against a live example are called out per case; the underlying API methods themselves are
/// stable, well-documented core Zabbix API (item.get, trigger.get, host.get, etc.).
extension DashboardManager {
    /// Resolves the current server URL and auth token, connecting to Zabbix first if needed.
    func connection() async throws -> (serverBaseURL: URL, authToken: String) {
        guard let configuration = try await settingsService.loadServerConfiguration(),
              let serverBaseURL = configuration.baseURL else {
            throw DashboardOpsError.missingServerConfiguration
        }

        let session: UserSession
        if let activeSession = await zabbixSessionService.activeSession() {
            session = activeSession
        } else {
            session = try await zabbixSessionService.connect()
        }

        guard let authToken = session.authToken else {
            throw DashboardOpsError.missingCredential
        }

        return (serverBaseURL, authToken)
    }

    /// Resolves each widget's data and refresh interval into `RenderableDashboardWidget`s.
    func renderableWidgets(
        for widgets: [ZabbixWidget],
        serverBaseURL: URL,
        authToken: String
    ) async throws -> [RenderableDashboardWidget] {
        await refreshSeverityPaletteIfNeeded(serverBaseURL: serverBaseURL, authToken: authToken)

        var result: [RenderableDashboardWidget] = []
        result.reserveCapacity(widgets.count)

        for widget in widgets {
            let kind = try await resolveWidgetKind(widget, serverBaseURL: serverBaseURL, authToken: authToken)
            result.append(
                RenderableDashboardWidget(
                    id: widget.widgetid,
                    title: widget.name?.isEmpty == false ? widget.name! : Self.defaultTitle(forWidgetType: widget.type),
                    frame: DashboardWidgetFrame(
                        x: widget.x.intValue,
                        y: widget.y.intValue,
                        width: widget.width.intValue,
                        height: widget.height.intValue
                    ),
                    refreshIntervalSeconds: Self.refreshIntervalSeconds(from: widget.fields),
                    hasHiddenHeader: widget.view_mode?.intValue == 1,
                    kind: kind
                )
            )
        }

        return result
    }

    /// Fetches this server's configured severity colors/names once per session and caches them
    /// in `SeverityPalette` for the view layer to read. Best-effort: some accounts may lack
    /// permission for `settings.get`, in which case severity coloring just falls back to
    /// Zabbix's stock palette rather than failing the whole dashboard load.
    private func refreshSeverityPaletteIfNeeded(serverBaseURL: URL, authToken: String) async {
        guard !hasFetchedSeverityPalette else { return }
        hasFetchedSeverityPalette = true

        guard let palette = try? await zabbixAPIClient.severityPalette(serverBaseURL: serverBaseURL, authToken: authToken) else {
            return
        }

        await SeverityPalette.update(hex: palette.colorsBySeverity, names: palette.namesBySeverity, blinkPeriodSeconds: palette.blinkPeriodSeconds)
    }

    func resolveWidgetKind(
        _ widget: ZabbixWidget,
        serverBaseURL: URL,
        authToken: String
    ) async throws -> DashboardWidgetKind {
        switch widget.type {
        case "clock":
            // "clock_type": 0 = analog, 1 = digital. Absent means analog — verified live against a
            // clock widget with no fields configured at all that still renders as an analog face,
            // matching Zabbix's own stock default for this widget.
            let isDigital = Self.fieldValue(widget.fields, name: "clock_type") == "1"
            return .clock(isDigital ? .digital : .analog)

        case "problems":
            let severities = Self.indexedValues(widget.fields, name: "severities").compactMap(Int.init)
            // Verified live: a real "Problems" widget here is configured with "show_lines": 40 and
            // two "exclude_groupids" (host groups the admin deliberately hid from this list) —
            // neither was being read, so the widget always showed a hardcoded 6 rows regardless of
            // its own configuration, and could show problems from groups meant to be excluded.
            let showLines = Self.fieldValue(widget.fields, name: "show_lines").flatMap(Int.init) ?? 20
            let excludedGroupIDs = Set(Self.indexedValues(widget.fields, name: "exclude_groupids"))

            let problems = try await zabbixAPIClient.problems(
                serverBaseURL: serverBaseURL,
                authToken: authToken,
                severities: severities.isEmpty ? nil : severities,
                groupIDs: try await scopedGroupIDs(from: widget, serverBaseURL: serverBaseURL, authToken: authToken),
                tags: Self.tagFilters(from: widget.fields),
                evalType: Self.tagEvalType(from: widget.fields),
                showSuppressed: Self.fieldValue(widget.fields, name: "show_suppressed") == "1"
            )

            let triggerHosts = try await zabbixAPIClient.triggerHosts(
                serverBaseURL: serverBaseURL,
                authToken: authToken,
                triggerIDs: Array(Set(problems.map(\.objectid)))
            )
            let hostByTriggerID = Dictionary(uniqueKeysWithValues: triggerHosts.compactMap { entry in
                entry.hosts.first.map { (entry.triggerid, $0) }
            })

            var visibleProblems = problems
            if !excludedGroupIDs.isEmpty {
                let hostIDs = Array(Set(hostByTriggerID.values.map(\.hostid)))
                let hostGroups = try await zabbixAPIClient.hostGroups(serverBaseURL: serverBaseURL, authToken: authToken, hostIDs: hostIDs)
                let groupIDsByHostID = Dictionary(uniqueKeysWithValues: hostGroups.map { ($0.hostid, Set($0.hostgroups.map(\.groupid))) })

                visibleProblems = problems.filter { problem in
                    guard let hostID = hostByTriggerID[problem.objectid]?.hostid else { return true }
                    return groupIDsByHostID[hostID, default: []].isDisjoint(with: excludedGroupIDs)
                }
            }

            return .problems(
                visibleProblems.prefix(showLines).map { problem in
                    DashboardProblem(
                        id: problem.eventid,
                        name: problem.name,
                        severity: problem.severity.intValue,
                        host: hostByTriggerID[problem.objectid]?.name,
                        since: Date(timeIntervalSince1970: TimeInterval(problem.clock) ?? 0)
                    )
                }
            )

        case "item":
            guard let itemID = Self.firstIndexedValue(widget.fields, name: "itemid") else {
                return .unsupported(rawType: widget.type)
            }

            let items = try await zabbixAPIClient.items(serverBaseURL: serverBaseURL, authToken: authToken, itemIDs: [itemID])
            guard let item = items.first else {
                return .unsupported(rawType: widget.type)
            }

            // When the widget aggregates over a time period (min/max/avg/count/sum/first/last),
            // show that computed value rather than the instantaneous last sample. A value map and
            // the up/down trend only apply to the raw last value, so they're suppressed when
            // aggregating.
            let aggregateFunction = Self.fieldValue(widget.fields, name: "aggregate_function").flatMap(Int.init) ?? 0
            let displayValue: String
            let mappedText: String?
            if aggregateFunction > 0 {
                let (from, to) = Self.timePeriod(from: widget.fields)
                let aggregated = try await aggregatedValue(itemID: item.itemid, valueType: item.value_type?.intValue ?? 0, function: aggregateFunction, from: from, to: to, serverBaseURL: serverBaseURL, authToken: authToken)
                displayValue = aggregated.map { String($0) } ?? "\u{2014}"
                mappedText = nil
            } else {
                displayValue = item.lastvalue ?? "\u{2014}"
                mappedText = item.lastvalue.flatMap { item.valuemap?.valueMap?.mappedText(for: $0) }
            }

            var trend: ItemValueTrend?
            if aggregateFunction == 0, let lastvalue = item.lastvalue.flatMap(Double.init), let prevvalue = item.prevvalue.flatMap(Double.init) {
                if lastvalue > prevvalue, let upColor = Self.fieldValue(widget.fields, name: "up_color") {
                    trend = .up(colorHex: upColor)
                } else if lastvalue < prevvalue, let downColor = Self.fieldValue(widget.fields, name: "down_color") {
                    trend = .down(colorHex: downColor)
                }
            }

            return .itemValue(
                name: item.name,
                value: displayValue,
                units: item.units ?? "",
                backgroundColorHex: Self.fieldValue(widget.fields, name: "bg_color"),
                trend: trend,
                lastUpdated: item.lastclock.flatMap(TimeInterval.init).map { Date(timeIntervalSince1970: $0) },
                mappedText: mappedText
            )

        case "problemsbysv":
            // Honor the same scoping the real widget applies: its own severity filter, "show
            // suppressed" option, and any host groups it deliberately excludes ("exclude_groupids",
            // verified live: this dashboard's widget hides groups 27 and 40). Counting every problem
            // regardless of these inflated the tallies well above what Zabbix shows for the same widget.
            let severities = Self.indexedValues(widget.fields, name: "severities").compactMap(Int.init)
            let excludedGroupIDs = Set(Self.indexedValues(widget.fields, name: "exclude_groupids"))

            let allProblems = try await zabbixAPIClient.problems(
                serverBaseURL: serverBaseURL,
                authToken: authToken,
                severities: severities.isEmpty ? nil : severities,
                groupIDs: try await scopedGroupIDs(from: widget, serverBaseURL: serverBaseURL, authToken: authToken),
                tags: Self.tagFilters(from: widget.fields),
                evalType: Self.tagEvalType(from: widget.fields),
                showSuppressed: Self.fieldValue(widget.fields, name: "show_suppressed") == "1"
            )
            let problems = try await problemsExcludingGroups(allProblems, excludedGroupIDs: excludedGroupIDs, serverBaseURL: serverBaseURL, authToken: authToken)

            var countsBySeverity = [Int: Int](uniqueKeysWithValues: (0...5).map { ($0, 0) })
            for problem in problems {
                countsBySeverity[problem.severity.intValue, default: 0] += 1
            }

            return .problemsBySeverity(
                (0...5).reversed().map { severity in
                    SeverityCount(severity: severity, count: countsBySeverity[severity] ?? 0)
                }
            )

        case "hostavail":
            let interfaceTypes = Self.indexedValues(widget.fields, name: "interface_type").compactMap(Int.init)
            let requestedTypes = interfaceTypes.isEmpty ? [1] : interfaceTypes

            let hosts = try await zabbixAPIClient.hostsWithInterfaces(serverBaseURL: serverBaseURL, authToken: authToken, groupIDs: try await scopedGroupIDs(from: widget, serverBaseURL: serverBaseURL, authToken: authToken))

            var rows: [HostInterfaceAvailability] = [
                Self.hostAvailabilityRow(name: "Total hosts", interfacesByHost: hosts.map(\.interfaces))
            ]
            rows.append(
                contentsOf: requestedTypes.sorted().map { type in
                    Self.hostAvailabilityRow(
                        name: Self.interfaceTypeName(type),
                        interfacesByHost: hosts.map { host in host.interfaces.filter { $0.type.intValue == type } }
                    )
                }
            )

            return .hostAvailability(rows)

        case "systeminfo":
            // Zabbix's own frontend determines "server is running" via a direct socket check to
            // the zabbix_server trapper port, which isn't reachable from this app. Reaching this
            // point at all means the API call just succeeded, so a live, authenticated session is
            // the closest available proxy for "the environment is up."
            let serverVersion = try await zabbixAPIClient.apiVersion(serverBaseURL: serverBaseURL)
            return .systemInformation(serverVersion: serverVersion, isRunning: true)

        case "gauge":
            return try await resolveGauge(widget, serverBaseURL: serverBaseURL, authToken: authToken)

        case "honeycomb":
            return try await resolveHoneycomb(widget, serverBaseURL: serverBaseURL, authToken: authToken)

        case "tophosts":
            return try await resolveTopHosts(widget, serverBaseURL: serverBaseURL, authToken: authToken)

        case "toptriggers":
            return try await resolveTopTriggers(widget, serverBaseURL: serverBaseURL, authToken: authToken)

        case "trigover":
            return try await resolveTriggerOverview(widget, serverBaseURL: serverBaseURL, authToken: authToken)

        case "problemhosts":
            return try await resolveProblemHosts(widget, serverBaseURL: serverBaseURL, authToken: authToken)

        case "actionlog":
            return try await resolveActionLog(widget, serverBaseURL: serverBaseURL, authToken: authToken)

        case "discovery":
            return try await resolveDiscoveryStatus(serverBaseURL: serverBaseURL, authToken: authToken)

        case "web":
            return try await resolveWebMonitoring(widget, serverBaseURL: serverBaseURL, authToken: authToken)

        case "itemhistory":
            return try await resolveItemHistory(widget, serverBaseURL: serverBaseURL, authToken: authToken)

        case "dataover":
            return try await resolveDataOverview(widget, serverBaseURL: serverBaseURL, authToken: authToken)

        case "svggraph":
            return try await resolveSVGGraph(widget, serverBaseURL: serverBaseURL, authToken: authToken)

        case "graph":
            return try await resolveClassicGraph(widget, serverBaseURL: serverBaseURL, authToken: authToken)

        case "piechart":
            return try await resolvePieChart(widget, serverBaseURL: serverBaseURL, authToken: authToken)

        case "geomap":
            return try await resolveGeomap(widget, serverBaseURL: serverBaseURL, authToken: authToken)

        case "map":
            return try await resolveNetworkMap(widget, serverBaseURL: serverBaseURL, authToken: authToken)

        case "navtree":
            return try await resolveMapNavigationTree(serverBaseURL: serverBaseURL, authToken: authToken)

        case "hostnavigator":
            return try await resolveHostNavigator(widget, serverBaseURL: serverBaseURL, authToken: authToken)

        case "itemnavigator":
            return try await resolveItemNavigator(widget, serverBaseURL: serverBaseURL, authToken: authToken)

        case "slareport":
            return try await resolveSLAReport(widget, serverBaseURL: serverBaseURL, authToken: authToken)

        // "graphprototype" (low-level discovery graphs) falls through to unsupported: resolving it
        // requires walking discovered hosts/items from a prototype pattern, a distinct and deeper
        // feature than every other widget here.
        //
        // "favgraphs"/"favmaps" (favorite graphs/maps) also fall through: favorites are per-user
        // frontend session state (Zabbix's "profile" idx storage), not exposed by the JSON-RPC API
        // — verified there is no favorite.get or equivalent method.
        default:
            return .unsupported(rawType: widget.type)
        }
    }

    // MARK: - Gauge

    /// Field names ("min"/"max"/"thresholds.N.threshold"/"thresholds.N.color") are Zabbix's
    /// documented gauge configuration options, not yet verified against a live example.
    private func resolveGauge(
        _ widget: ZabbixWidget,
        serverBaseURL: URL,
        authToken: String
    ) async throws -> DashboardWidgetKind {
        guard let itemID = Self.firstIndexedValue(widget.fields, name: "itemid") else {
            return .unsupported(rawType: widget.type)
        }

        let items = try await zabbixAPIClient.items(serverBaseURL: serverBaseURL, authToken: authToken, itemIDs: [itemID])
        guard let item = items.first, let value = item.lastvalue.flatMap(Double.init) else {
            return .unsupported(rawType: widget.type)
        }

        let minValue = Self.fieldValue(widget.fields, name: "min").flatMap(Double.init) ?? 0
        let maxValue = Self.fieldValue(widget.fields, name: "max").flatMap(Double.init) ?? 100

        let thresholds = Self.indexedFieldGroups(widget.fields, prefix: "thresholds")
            .compactMap { group -> GaugeThreshold? in
                guard let thresholdValue = group["threshold"].flatMap(Double.init), let color = group["color"] else {
                    return nil
                }
                return GaugeThreshold(value: thresholdValue, colorHex: color)
            }
            .sorted { $0.value < $1.value }

        return .gauge(
            GaugeReading(
                name: item.name,
                value: value,
                minValue: minValue,
                maxValue: maxValue,
                units: item.units ?? "",
                thresholds: thresholds,
                fixedArcColorHex: Self.fieldValue(widget.fields, name: "value_arc_color"),
                mappedText: item.lastvalue.flatMap { item.valuemap?.valueMap?.mappedText(for: $0) }
            )
        )
    }

    /// Fetches items matching any of a widget's item name patterns (`items.N`), unioned and
    /// de-duplicated by item ID. An empty pattern list means "all items in the group/host scope",
    /// matching Zabbix; each pattern's wildcards are honored by `item.get`'s search.
    private func itemsMatchingPatterns(
        _ patterns: [String],
        groupIDs: [String]?,
        hostIDs: [String]?,
        tags: [ZabbixTagFilter]? = nil,
        evalType: Int? = nil,
        serverBaseURL: URL,
        authToken: String
    ) async throws -> [ZabbixItemWithHost] {
        let cleaned = patterns.filter { !$0.isEmpty }
        guard !cleaned.isEmpty else {
            return try await zabbixAPIClient.itemsMatching(serverBaseURL: serverBaseURL, authToken: authToken, groupIDs: groupIDs, hostIDs: hostIDs, namePattern: nil, tags: tags, evalType: evalType)
        }

        var result: [ZabbixItemWithHost] = []
        var seen = Set<String>()
        for pattern in cleaned {
            let matched = try await zabbixAPIClient.itemsMatching(serverBaseURL: serverBaseURL, authToken: authToken, groupIDs: groupIDs, hostIDs: hostIDs, namePattern: pattern, tags: tags, evalType: evalType)
            for item in matched where seen.insert(item.itemid).inserted {
                result.append(item)
            }
        }
        return result
    }

    // MARK: - Honeycomb

    private func resolveHoneycomb(
        _ widget: ZabbixWidget,
        serverBaseURL: URL,
        authToken: String
    ) async throws -> DashboardWidgetKind {
        let groupIDs = Self.indexedValues(widget.fields, name: "groupids")
        let hostIDs = Self.indexedValues(widget.fields, name: "hostids")
        // The item pattern lives in `items.N` (Zabbix's CWidgetFieldPatternSelectItem), not the
        // "itempatterns.N.itemname" this used to read — so the pattern was never applied and an
        // unfiltered fetch returned every item on the server.
        let itemPatterns = Self.indexedValues(widget.fields, name: "items")
        let tags = Self.tagFilters(from: widget.fields)

        let items = try await itemsMatchingPatterns(
            itemPatterns,
            groupIDs: groupIDs.isEmpty ? nil : groupIDs,
            hostIDs: hostIDs.isEmpty ? nil : hostIDs,
            tags: tags,
            evalType: Self.tagEvalType(from: widget.fields),
            serverBaseURL: serverBaseURL,
            authToken: authToken
        )

        return .honeycomb(
            items.prefix(60).map { item in
                HoneycombCell(
                    id: item.itemid,
                    primaryLabel: item.hosts.first?.name ?? "",
                    secondaryLabel: item.name,
                    value: Self.mappedItemValue(rawValue: item.lastvalue, valueMap: item.valuemap?.valueMap)
                )
            }
        )
    }

    // MARK: - Top hosts

    /// Bounds how many candidate hosts are ranked, so a "top N" over a large group stays a few
    /// dozen round trips on a TV rather than one per host on the whole server.
    private static let topHostsCandidateCap = 50

    /// Ranks hosts by a chosen column and shows the top/bottom N — the actual point of the widget.
    /// Each item column is aggregated over the widget's time period when configured (`aggregate_
    /// function`) rather than showing the instantaneous last value, and value-mapped for display.
    private func resolveTopHosts(
        _ widget: ZabbixWidget,
        serverBaseURL: URL,
        authToken: String
    ) async throws -> DashboardWidgetKind {
        let groupIDs = Self.indexedValues(widget.fields, name: "groupids")
        let hostIDs = Self.indexedValues(widget.fields, name: "hostids")

        let hosts = try await zabbixAPIClient.hosts(
            serverBaseURL: serverBaseURL,
            authToken: authToken,
            groupIDs: groupIDs.isEmpty ? nil : groupIDs,
            hostIDs: hostIDs.isEmpty ? nil : hostIDs
        )

        let columnGroups = Self.indexedFieldGroups(widget.fields, prefix: "columns")
        let columnTitles = columnGroups.isEmpty ? ["Host"] : columnGroups.map { $0["name"] ?? "Column" }

        // Ranking config: which column drives the order, whether it's top (highest) or bottom
        // (lowest), and how many rows to show.
        let sortColumnIndex = Self.fieldValue(widget.fields, name: "column").flatMap(Int.init) ?? 0
        let isBottomN = Self.fieldValue(widget.fields, name: "order").flatMap(Int.init) == 3
        let showLines = Self.fieldValue(widget.fields, name: "show_lines").flatMap(Int.init) ?? 10
        let (from, to) = Self.timePeriod(from: widget.fields)

        var ranked: [(row: TopHostsRow, sortValue: Double?)] = []
        for host in hosts.prefix(Self.topHostsCandidateCap) {
            guard !columnGroups.isEmpty else {
                ranked.append((TopHostsRow(id: host.hostid, hostName: host.name, values: [host.name]), nil))
                continue
            }

            var values: [String] = []
            var sortValue: Double?
            for (index, column) in columnGroups.enumerated() {
                let cell = try await topHostsColumnValue(column, host: host, from: from, to: to, serverBaseURL: serverBaseURL, authToken: authToken)
                values.append(cell.display)
                if index == sortColumnIndex { sortValue = cell.numeric }
            }
            ranked.append((TopHostsRow(id: host.hostid, hostName: host.name, values: values), sortValue))
        }

        return .topHosts(columns: columnTitles, rows: Self.rankTopHostsRows(ranked, isBottomN: isBottomN, limit: showLines))
    }

    /// Orders scored Top hosts rows — highest first for top-N, lowest first for bottom-N — with
    /// unscored rows (no numeric value in the ranking column) always last, then limits to `limit`.
    static func rankTopHostsRows<Row>(
        _ scored: [(row: Row, sortValue: Double?)],
        isBottomN: Bool,
        limit: Int
    ) -> [Row] {
        scored.sorted { lhs, rhs in
            switch (lhs.sortValue, rhs.sortValue) {
            case let (l?, r?): return isBottomN ? l < r : l > r
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return false
            }
        }.prefix(limit).map(\.row)
    }

    /// Resolves one Top hosts cell to a display string plus, for item columns, the numeric value the
    /// row is ranked by. Item columns aggregate over the widget's time period when configured;
    /// otherwise they show the value-mapped last reading.
    private func topHostsColumnValue(
        _ column: [String: String],
        host: ZabbixHostListEntry,
        from: Date,
        to: Date,
        serverBaseURL: URL,
        authToken: String
    ) async throws -> (display: String, numeric: Double?) {
        // A text column is a fixed label with nothing to rank by.
        if let text = column["text"], !text.isEmpty, (column["item"] ?? "").isEmpty {
            return (text, nil)
        }

        guard let itemPattern = column["item"], !itemPattern.isEmpty else {
            return (host.name, nil)
        }

        let items = try await zabbixAPIClient.itemsMatching(
            serverBaseURL: serverBaseURL,
            authToken: authToken,
            hostIDs: [host.hostid],
            namePattern: itemPattern
        )
        guard let item = items.first else { return ("\u{2014}", nil) }

        let aggregateFunction = column["aggregate_function"].flatMap(Int.init) ?? 0
        if aggregateFunction > 0 {
            let aggregated = try await aggregatedValue(
                itemID: item.itemid,
                valueType: item.value_type?.intValue ?? 0,
                function: aggregateFunction,
                from: from,
                to: to,
                serverBaseURL: serverBaseURL,
                authToken: authToken
            )
            return (aggregated.map { String($0) } ?? "\u{2014}", aggregated)
        }

        let display = Self.mappedItemValue(rawValue: item.lastvalue, valueMap: item.valuemap?.valueMap)
        return (display, item.lastvalue.flatMap(Double.init))
    }

    // MARK: - Top triggers

    /// Shows current problems sorted by severity, limited by the widget's "show_lines" field. This
    /// does not implement Zabbix's true "highest number of problems" frequency ranking, which
    /// requires aggregating event history over a time range rather than current state.
    private func resolveTopTriggers(
        _ widget: ZabbixWidget,
        serverBaseURL: URL,
        authToken: String
    ) async throws -> DashboardWidgetKind {
        let limit = Self.fieldValue(widget.fields, name: "show_lines").flatMap(Int.init) ?? 20
        let severities = Self.indexedValues(widget.fields, name: "severities").compactMap(Int.init)

        let problems = try await zabbixAPIClient.problems(
            serverBaseURL: serverBaseURL,
            authToken: authToken,
            severities: severities.isEmpty ? nil : severities,
            groupIDs: try await scopedGroupIDs(from: widget, serverBaseURL: serverBaseURL, authToken: authToken),
            tags: Self.tagFilters(from: widget.fields),
            evalType: Self.tagEvalType(from: widget.fields)
        )

        let hostByTriggerID = try await hostNamesByTriggerID(
            problems.map(\.objectid),
            serverBaseURL: serverBaseURL,
            authToken: authToken
        )

        let sortedProblems = problems.sorted { $0.severity.intValue > $1.severity.intValue }.prefix(limit)

        return .topTriggers(
            sortedProblems.map { problem in
                DashboardProblem(
                    id: problem.eventid,
                    name: problem.name,
                    severity: problem.severity.intValue,
                    host: hostByTriggerID[problem.objectid],
                    since: Date(timeIntervalSince1970: TimeInterval(problem.clock) ?? 0)
                )
            }
        )
    }

    // MARK: - Trigger overview

    private func resolveTriggerOverview(
        _ widget: ZabbixWidget,
        serverBaseURL: URL,
        authToken: String
    ) async throws -> DashboardWidgetKind {
        let hostIDs = Self.indexedValues(widget.fields, name: "hostids")

        // "Show": 1 = Recent problems (default), 2 = Problems, 3 = Any. Only "Any" renders OK cells,
        // so it's the one case where every trigger is fetched rather than just PROBLEM-state ones.
        // Recent-vs-Problems differ only by recovery recency, which needs event history; both are
        // treated here as current PROBLEM state.
        let showAny = Self.fieldValue(widget.fields, name: "show").flatMap(Int.init) == 3

        let triggers = try await zabbixAPIClient.activeTriggers(
            serverBaseURL: serverBaseURL,
            authToken: authToken,
            groupIDs: try await scopedGroupIDs(from: widget, serverBaseURL: serverBaseURL, authToken: authToken),
            hostIDs: hostIDs.isEmpty ? nil : hostIDs,
            onlyProblems: !showAny,
            tags: Self.tagFilters(from: widget.fields),
            evalType: Self.tagEvalType(from: widget.fields)
        )

        var rowsByHostID: [String: TriggerOverviewRow] = [:]
        var hostOrder: [String] = []

        for trigger in triggers {
            guard let host = trigger.hosts.first else { continue }
            // When only PROBLEM-state triggers were fetched, `value` is unrequested, so every
            // trigger here is in problem state; otherwise read the trigger's actual current state.
            let isProblem = showAny ? (trigger.value?.intValue ?? 1) == 1 : true
            let indicator = TriggerIndicator(id: trigger.triggerid, name: trigger.description, severity: trigger.priority.intValue, isProblem: isProblem)

            if let existing = rowsByHostID[host.hostid] {
                rowsByHostID[host.hostid] = TriggerOverviewRow(id: existing.id, hostName: existing.hostName, triggers: existing.triggers + [indicator])
            } else {
                rowsByHostID[host.hostid] = TriggerOverviewRow(id: host.hostid, hostName: host.name, triggers: [indicator])
                hostOrder.append(host.hostid)
            }
        }

        return .triggerOverview(hostOrder.compactMap { rowsByHostID[$0] })
    }

    // MARK: - Problem hosts

    private func resolveProblemHosts(_ widget: ZabbixWidget, serverBaseURL: URL, authToken: String) async throws -> DashboardWidgetKind {
        // Honor the widget's own scope — severity, host groups (incl. nested), tags, and suppression
        // — the same way the other problem widgets do; this resolver previously took no widget at
        // all and counted every host on the server.
        let severities = Self.indexedValues(widget.fields, name: "severities").compactMap(Int.init)
        var resolved = try await activeProblemsWithHostID(
            serverBaseURL: serverBaseURL,
            authToken: authToken,
            severities: severities.isEmpty ? nil : severities,
            groupIDs: try await scopedGroupIDs(from: widget, serverBaseURL: serverBaseURL, authToken: authToken),
            tags: Self.tagFilters(from: widget.fields),
            evalType: Self.tagEvalType(from: widget.fields),
            showSuppressed: Self.fieldValue(widget.fields, name: "show_suppressed") == "1"
        )

        // exclude_groupids drops problems whose host is in an excluded group (incl. nested), reusing
        // the shared helper that operates on the problems themselves.
        let excludedGroupIDs = Set(Self.indexedValues(widget.fields, name: "exclude_groupids"))
        if !excludedGroupIDs.isEmpty {
            let keptEventIDs = Set(try await problemsExcludingGroups(resolved.map(\.problem), excludedGroupIDs: excludedGroupIDs, serverBaseURL: serverBaseURL, authToken: authToken).map(\.eventid))
            resolved = resolved.filter { keptEventIDs.contains($0.problem.eventid) }
        }

        let hostIDs = Array(Set(resolved.map(\.hostID)))
        let hostGroups = try await zabbixAPIClient.hostGroups(serverBaseURL: serverBaseURL, authToken: authToken, hostIDs: hostIDs)
        let groupsByHostID = Dictionary(uniqueKeysWithValues: hostGroups.map { ($0.hostid, $0.hostgroups) })

        // "Problem hosts" counts distinct HOSTS with an active problem per group, matching
        // Zabbix's own widget (not the total number of problems — a single host with 5 open
        // problems is still 1 problem host, not 5).
        var hostIDsByGroup: [String: (name: String, hostIDs: Set<String>, maxSeverity: Int)] = [:]

        for entry in resolved {
            guard let groups = groupsByHostID[entry.hostID] else { continue }

            for group in groups {
                var summary = hostIDsByGroup[group.groupid] ?? (name: group.name, hostIDs: [], maxSeverity: 0)
                summary.hostIDs.insert(entry.hostID)
                summary.maxSeverity = max(summary.maxSeverity, entry.problem.severity.intValue)
                hostIDsByGroup[group.groupid] = summary
            }
        }

        return .problemsByHostGroup(
            hostIDsByGroup.map { groupID, summary in
                HostGroupProblemSummary(id: groupID, groupName: summary.name, count: summary.hostIDs.count, maxSeverity: summary.maxSeverity)
            }.sorted { $0.maxSeverity == $1.maxSeverity ? $0.count > $1.count : $0.maxSeverity > $1.maxSeverity }
        )
    }

    // MARK: - Geomap

    private func resolveGeomap(
        _ widget: ZabbixWidget,
        serverBaseURL: URL,
        authToken: String
    ) async throws -> DashboardWidgetKind {
        let groupIDs = Self.indexedValues(widget.fields, name: "groupids")
        let hostIDs = Self.indexedValues(widget.fields, name: "hostids")

        let hosts = try await zabbixAPIClient.hostsWithInventory(
            serverBaseURL: serverBaseURL,
            authToken: authToken,
            groupIDs: groupIDs.isEmpty ? nil : groupIDs,
            hostIDs: hostIDs.isEmpty ? nil : hostIDs
        )

        let severityByHostID = try await maxSeverityByHostID(serverBaseURL: serverBaseURL, authToken: authToken)

        let markers = hosts.compactMap { host -> GeoMapMarker? in
            guard let latitude = host.inventory.locationLatitude.flatMap(Double.init),
                  let longitude = host.inventory.locationLongitude.flatMap(Double.init) else {
                return nil
            }
            return GeoMapMarker(
                id: host.hostid,
                hostName: host.name,
                latitude: latitude,
                longitude: longitude,
                severity: severityByHostID[host.hostid] ?? 0
            )
        }

        return .geomap(markers)
    }

    // MARK: - Network map

    /// The "sysmapid" field name (a single scalar map reference) is Zabbix's standard convention;
    /// the alternative "compatible widget as data source" configuration isn't implemented — this
    /// resolves only a directly configured map.
    private func resolveNetworkMap(
        _ widget: ZabbixWidget,
        serverBaseURL: URL,
        authToken: String
    ) async throws -> DashboardWidgetKind {
        guard let mapID = Self.fieldValue(widget.fields, name: "sysmapid"),
              let map = try await zabbixAPIClient.networkMap(serverBaseURL: serverBaseURL, authToken: authToken, mapID: mapID) else {
            return .unsupported(rawType: widget.type)
        }

        let backgroundImageData = try await backgroundImageData(forImageID: map.backgroundid, serverBaseURL: serverBaseURL, authToken: authToken)

        let hostIDs = map.selements.compactMap { $0.elementtype.intValue == 0 ? $0.elements.first?.hostid : nil }
        let hosts = try await zabbixAPIClient.hosts(serverBaseURL: serverBaseURL, authToken: authToken, hostIDs: hostIDs.isEmpty ? nil : hostIDs)
        let hostNameByID = Dictionary(uniqueKeysWithValues: hosts.map { ($0.hostid, $0.name) })
        let severityByHostID = try await maxSeverityByHostID(serverBaseURL: serverBaseURL, authToken: authToken)

        let activeTriggerIDs = Set(try await zabbixAPIClient.problems(serverBaseURL: serverBaseURL, authToken: authToken).map(\.objectid))

        // Elements typically reuse a small set of icons (e.g. every switch shares one "Switch"
        // icon), so the unique set is fetched once rather than once per element.
        let uniqueIconIDs = Set(map.selements.map(\.iconid_off).filter { $0 != "0" && !$0.isEmpty })
        let icons = try await zabbixAPIClient.images(serverBaseURL: serverBaseURL, authToken: authToken, imageIDs: Array(uniqueIconIDs))
        let iconDataByID = Dictionary(uniqueKeysWithValues: icons.compactMap { icon -> (String, Data)? in
            guard let data = Data(base64Encoded: icon.image) else { return nil }
            return (icon.imageid, data)
        })

        var severityByElementID: [String: Int] = [:]
        let elements = map.selements.map { selement -> NetworkMapElement in
            let hostID = selement.elementtype.intValue == 0 ? selement.elements.first?.hostid : nil
            let label = hostID.flatMap { hostNameByID[$0] } ?? Self.cleanedMapLabel(selement.label)
            let severity = hostID.flatMap { severityByHostID[$0] } ?? 0
            severityByElementID[selement.selementid] = severity

            return NetworkMapElement(
                id: selement.selementid,
                label: label,
                x: selement.x.intValue,
                y: selement.y.intValue,
                severity: severity,
                iconImageData: iconDataByID[selement.iconid_off]
            )
        }

        let elementsByID = Dictionary(uniqueKeysWithValues: elements.map { ($0.id, $0) })
        let links = map.links.compactMap { link -> NetworkMapLink? in
            guard let from = elementsByID[link.selementid1], let to = elementsByID[link.selementid2] else {
                return nil
            }
            let overrideColor = link.linktriggers.first { activeTriggerIDs.contains($0.triggerid) }?.color

            return NetworkMapLink(id: link.linkid, fromX: from.x, fromY: from.y, toX: to.x, toY: to.y, colorHex: overrideColor ?? link.color)
        }

        return .networkMap(
            NetworkMapDiagram(
                width: map.width.intValue,
                height: map.height.intValue,
                backgroundImageData: backgroundImageData,
                elements: elements,
                links: links
            )
        )
    }

    /// Fetches and decodes a map's background image. Returns `nil` when no background is
    /// configured ("0", Zabbix's convention for "none") or the image fails to decode.
    private func backgroundImageData(forImageID imageID: String, serverBaseURL: URL, authToken: String) async throws -> Data? {
        guard imageID != "0", !imageID.isEmpty,
              let image = try await zabbixAPIClient.image(serverBaseURL: serverBaseURL, authToken: authToken, imageID: imageID) else {
            return nil
        }
        return Data(base64Encoded: image.image)
    }

    // MARK: - Map navigation tree

    /// Renders as a flat list of available map names. The tree's whole purpose is letting a user
    /// click through a hierarchy to choose which map a paired Map widget shows — a selection model
    /// with no clear unattended-kiosk equivalent, per the static-display treatment agreed for
    /// navigator-style widgets.
    private func resolveMapNavigationTree(serverBaseURL: URL, authToken: String) async throws -> DashboardWidgetKind {
        let maps = try await zabbixAPIClient.maps(serverBaseURL: serverBaseURL, authToken: authToken)
        return .mapList(maps.map { MapListEntry(id: $0.sysmapid, name: $0.name) })
    }

    // MARK: - Host navigator

    /// Static list, per the agreed treatment for navigator-style widgets on an unattended kiosk
    /// display — the interactive drill-down into other widgets isn't implemented.
    private func resolveHostNavigator(
        _ widget: ZabbixWidget,
        serverBaseURL: URL,
        authToken: String
    ) async throws -> DashboardWidgetKind {
        // Read the widget's real scope: hosts are name patterns (`hosts.N`, not the "hostids" this
        // used to read), status is Any/Enabled/Disabled (not hardcoded enabled-only), plus host
        // tags, severities, and a row limit.
        let groupIDs = Self.indexedValues(widget.fields, name: "groupids")
        let namePatterns = Self.indexedValues(widget.fields, name: "hosts")
        let status = Self.fieldValue(widget.fields, name: "status").flatMap(Int.init)
        let showLines = Self.fieldValue(widget.fields, name: "show_lines").flatMap(Int.init) ?? 100
        let severities = Self.indexedValues(widget.fields, name: "severities").compactMap(Int.init)

        let hosts = try await zabbixAPIClient.hostsMatching(
            serverBaseURL: serverBaseURL,
            authToken: authToken,
            groupIDs: groupIDs.isEmpty ? nil : groupIDs,
            namePatterns: namePatterns,
            status: status,
            tags: Self.tagFilters(from: widget.fields, prefix: "host_tags"),
            evalType: Self.tagEvalType(from: widget.fields, field: "host_tags_evaltype")
        )

        let resolved = try await activeProblemsWithHostID(serverBaseURL: serverBaseURL, authToken: authToken, severities: severities.isEmpty ? nil : severities)
        var countByHostID: [String: Int] = [:]
        var maxSeverityByHostID: [String: Int] = [:]
        for entry in resolved {
            countByHostID[entry.hostID, default: 0] += 1
            maxSeverityByHostID[entry.hostID] = max(maxSeverityByHostID[entry.hostID] ?? 0, entry.problem.severity.intValue)
        }

        return .hostList(
            hosts.prefix(showLines).map { host in
                HostListEntry(
                    id: host.hostid,
                    name: host.name,
                    problemCount: countByHostID[host.hostid] ?? 0,
                    maxSeverity: maxSeverityByHostID[host.hostid] ?? 0
                )
            }
        )
    }

    // MARK: - Item navigator

    /// Static list, per the agreed treatment for navigator-style widgets.
    private func resolveItemNavigator(
        _ widget: ZabbixWidget,
        serverBaseURL: URL,
        authToken: String
    ) async throws -> DashboardWidgetKind {
        let groupIDs = Self.indexedValues(widget.fields, name: "groupids")
        let hostIDs = Self.indexedValues(widget.fields, name: "hostids")
        // The item pattern lives in `items.N`, not the singular `item` field this used to read, so
        // the pattern was never applied and the navigator listed every item in scope.
        let itemPatterns = Self.indexedValues(widget.fields, name: "items")
        let showLines = Self.fieldValue(widget.fields, name: "show_lines").flatMap(Int.init) ?? 100

        // Item navigator stores its item-tag filter under `item_tags.*` (mirroring Host navigator's
        // `host_tags.*`); fall back to the plain `tags.*` convention the classic item widgets use so
        // whichever the widget actually persists is applied. A missing field just means no filter.
        var tags = Self.tagFilters(from: widget.fields, prefix: "item_tags")
        var tagEvalType = Self.tagEvalType(from: widget.fields, field: "item_tags_evaltype")
        if tags.isEmpty {
            tags = Self.tagFilters(from: widget.fields)
            tagEvalType = Self.tagEvalType(from: widget.fields)
        }

        let items = try await itemsMatchingPatterns(
            itemPatterns,
            groupIDs: groupIDs.isEmpty ? nil : groupIDs,
            hostIDs: hostIDs.isEmpty ? nil : hostIDs,
            tags: tags,
            evalType: tagEvalType,
            serverBaseURL: serverBaseURL,
            authToken: authToken
        )

        return .itemList(
            items.prefix(showLines).map { item in
                ItemListEntry(
                    id: item.itemid,
                    name: item.name,
                    hostName: item.hosts.first?.name ?? "",
                    lastValue: Self.mappedItemValue(rawValue: item.lastvalue, valueMap: item.valuemap?.valueMap),
                    units: item.units ?? ""
                )
            }
        )
    }

    // MARK: - SLA report

    /// Shows the configured SLA's target. (Computing the achieved SLI over the report's periods
    /// via `sla.getsli` is a larger follow-up — see the widget coverage audit.)
    ///
    /// The SLA reference is stored as the indexed `slaid.0`, not a flat `slaid`; reading the wrong
    /// name left the selector nil, so `sla.get` returned every SLA on the server instead of the one
    /// the widget selected.
    private func resolveSLAReport(
        _ widget: ZabbixWidget,
        serverBaseURL: URL,
        authToken: String
    ) async throws -> DashboardWidgetKind {
        let slaID = Self.firstIndexedValue(widget.fields, name: "slaid")
        let slas = try await zabbixAPIClient.slas(serverBaseURL: serverBaseURL, authToken: authToken, slaIDs: slaID.map { [$0] })

        return .slaReport(
            slas.map { sla in
                SLAReportEntry(id: sla.slaid, name: sla.name, targetSLO: "\(sla.slo)%")
            }
        )
    }

    // MARK: - Action log

    /// Bounded to the last 7 days: an unbounded `alert.get` call timed out against a live server
    /// with years of alert history.
    private func resolveActionLog(
        _ widget: ZabbixWidget,
        serverBaseURL: URL,
        authToken: String
    ) async throws -> DashboardWidgetKind {
        let sinceUnixTime = Int(Date().timeIntervalSince1970) - 7 * 24 * 3600
        // "Show lines" caps the number of recent alerts listed (Zabbix's default is 25); alert.get
        // already returns them newest-first, so this bounds the fetch to the configured row count
        // rather than the client's blanket 50.
        let showLines = Self.fieldValue(widget.fields, name: "show_lines").flatMap(Int.init) ?? 25
        let alerts = try await zabbixAPIClient.alerts(serverBaseURL: serverBaseURL, authToken: authToken, sinceUnixTime: sinceUnixTime, limit: showLines)

        return .actionLog(
            alerts.map { alert in
                let isRemoteCommand = alert.alerttype.intValue == 1
                let recipient = alert.sendto?.isEmpty == false ? alert.sendto! : (isRemoteCommand ? "Remote command" : "Unknown recipient")
                let subject = alert.subject?.isEmpty == false ? alert.subject! : (alert.message ?? "")

                return ActionLogEntry(
                    id: alert.alertid,
                    recipient: recipient,
                    subject: subject,
                    status: alert.status.intValue,
                    date: Date(timeIntervalSince1970: TimeInterval(alert.clock) ?? 0)
                )
            }
        )
    }

    // MARK: - Discovery status

    private func resolveDiscoveryStatus(serverBaseURL: URL, authToken: String) async throws -> DashboardWidgetKind {
        let rules = try await zabbixAPIClient.discoveryRules(serverBaseURL: serverBaseURL, authToken: authToken)
        let discoveredHosts = try await zabbixAPIClient.discoveredHosts(
            serverBaseURL: serverBaseURL,
            authToken: authToken,
            ruleIDs: rules.map(\.druleid)
        )
        let hostsByRule = Dictionary(grouping: discoveredHosts, by: \.druleid)

        return .discoveryStatus(
            rules.map { rule in
                let hosts = hostsByRule[rule.druleid] ?? []
                return DiscoveryRuleStatus(
                    id: rule.druleid,
                    name: rule.name,
                    isEnabled: rule.status.intValue == 0,
                    upCount: hosts.filter { $0.status.intValue == 0 }.count,
                    downCount: hosts.filter { $0.status.intValue == 1 }.count
                )
            }
        )
    }

    // MARK: - Web monitoring

    private func resolveWebMonitoring(
        _ widget: ZabbixWidget,
        serverBaseURL: URL,
        authToken: String
    ) async throws -> DashboardWidgetKind {
        let groupIDs = Self.indexedValues(widget.fields, name: "groupids")
        let hostIDs = Self.indexedValues(widget.fields, name: "hostids")

        let scenarios = try await zabbixAPIClient.webScenarios(
            serverBaseURL: serverBaseURL,
            authToken: authToken,
            groupIDs: groupIDs.isEmpty ? nil : groupIDs,
            hostIDs: hostIDs.isEmpty ? nil : hostIDs
        )

        return .webMonitoring(
            scenarios.map { scenario in
                WebScenarioSummary(id: scenario.httptestid, name: scenario.name, hostName: scenario.hosts.first?.name)
            }
        )
    }

    // MARK: - Item history

    private func resolveItemHistory(
        _ widget: ZabbixWidget,
        serverBaseURL: URL,
        authToken: String
    ) async throws -> DashboardWidgetKind {
        // The Item history widget stores its items as columns (`columns.N.itemid`), not a flat
        // `itemids` array — reading the wrong field left the guard below always failing, so the
        // widget rendered nothing for every real 7.0 configuration.
        let itemIDs = Self.indexedFieldGroups(widget.fields, prefix: "columns").compactMap { $0["itemid"] }.filter { !$0.isEmpty }
        guard !itemIDs.isEmpty else {
            return .unsupported(rawType: widget.type)
        }

        // "Show lines" controls how many recent values per item are listed (Zabbix's default is 25),
        // rather than the hardcoded 5.
        let showLines = Self.fieldValue(widget.fields, name: "show_lines").flatMap(Int.init) ?? 25

        // Honor the widget's configured time period (the same resolver every time-based widget uses)
        // instead of a fixed window ending at now, so a widget scoped to, say, "yesterday" lists
        // that window's values. history.get returns newest-first from `from`; values newer than the
        // window's upper bound are trimmed before taking the most recent `showLines`.
        let (from, to) = Self.timePeriod(from: widget.fields)
        let toEpoch = to.timeIntervalSince1970

        let items = try await zabbixAPIClient.items(serverBaseURL: serverBaseURL, authToken: authToken, itemIDs: itemIDs)

        var series: [ItemHistorySeries] = []
        for item in items {
            let historyValueType = item.value_type?.intValue ?? 0
            let values = try await zabbixAPIClient.history(
                serverBaseURL: serverBaseURL,
                authToken: authToken,
                itemID: item.itemid,
                historyValueType: historyValueType,
                sinceUnixTime: Int(from.timeIntervalSince1970),
                limit: Self.maxHistoryPointsFetched
            )

            let windowed = values
                .filter { (TimeInterval($0.clock) ?? 0) <= toEpoch }
                .prefix(showLines)

            series.append(
                ItemHistorySeries(
                    id: item.itemid,
                    itemName: item.name,
                    units: item.units ?? "",
                    values: windowed.map { value in
                        ItemHistoryPoint(
                            id: "\(item.itemid).\(value.clock)",
                            value: Self.mappedItemValue(rawValue: value.value, valueMap: item.valuemap?.valueMap),
                            date: Date(timeIntervalSince1970: TimeInterval(value.clock) ?? 0)
                        )
                    }
                )
            )
        }

        return .itemHistory(series)
    }

    // MARK: - Data overview

    private func resolveDataOverview(
        _ widget: ZabbixWidget,
        serverBaseURL: URL,
        authToken: String
    ) async throws -> DashboardWidgetKind {
        let groupIDs = Self.indexedValues(widget.fields, name: "groupids")
        let hostIDs = Self.indexedValues(widget.fields, name: "hostids")
        let tags = Self.tagFilters(from: widget.fields)

        let items = try await zabbixAPIClient.itemsMatching(
            serverBaseURL: serverBaseURL,
            authToken: authToken,
            groupIDs: groupIDs.isEmpty ? nil : groupIDs,
            hostIDs: hostIDs.isEmpty ? nil : hostIDs,
            tags: tags,
            evalType: Self.tagEvalType(from: widget.fields)
        )

        return .dataOverview(
            items.prefix(100).map { item in
                DataOverviewEntry(
                    id: item.itemid,
                    hostName: item.hosts.first?.name ?? "",
                    itemName: item.name,
                    value: Self.mappedItemValue(rawValue: item.lastvalue, valueMap: item.valuemap?.valueMap),
                    units: item.units ?? ""
                )
            }
        )
    }

    // MARK: - SVG graph

    /// Dataset fields ("ds.N.hosts.0", "ds.N.items.0", "ds.N.color") verified against a live
    /// Zabbix 7.0 server. Also verified live: a single "ds.N" dataset can list several item name
    /// patterns ("ds.N.items.0", "ds.N.items.1", ...) that all share the dataset's one configured
    /// base color — Zabbix auto-shades each matched item so they stay distinguishable — and a
    /// widget can additionally define "or.N" ("override") entries, each a single manually-added
    /// item with its own explicit color layered on top of the pattern-matched datasets. Missing
    /// either of these dropped real lines/colors that appear on the live server's graphs.
    private func resolveSVGGraph(
        _ widget: ZabbixWidget,
        serverBaseURL: URL,
        authToken: String
    ) async throws -> DashboardWidgetKind {
        let datasets = Self.indexedFieldGroups(widget.fields, prefix: "ds")
        let overrides = Self.indexedFieldGroups(widget.fields, prefix: "or")
        guard !datasets.isEmpty || !overrides.isEmpty else {
            return .unsupported(rawType: widget.type)
        }

        let (windowStart, windowEnd) = Self.timePeriod(from: widget.fields)
        var series: [ChartSeries] = []

        for dataset in datasets {
            let hostNames = Self.valuesWithNumberedSuffix(dataset, prefix: "hosts.")
            let itemPatterns = Self.valuesWithNumberedSuffix(dataset, prefix: "items.")
            guard !hostNames.isEmpty, !itemPatterns.isEmpty else { continue }

            let hosts = try await zabbixAPIClient.hostsByName(serverBaseURL: serverBaseURL, authToken: authToken, names: hostNames)
            let baseColorHex = dataset["color"] ?? "3DC9B0"
            let fillOpacity = Self.fillOpacity(fromTransparencyField: dataset["transparency"])

            var matchIndex = 0
            for host in hosts {
                for itemPattern in itemPatterns {
                    let items = try await zabbixAPIClient.itemsMatching(
                        serverBaseURL: serverBaseURL,
                        authToken: authToken,
                        hostIDs: [host.hostid],
                        namePattern: itemPattern
                    )

                    for item in items {
                        let points = try await recentPoints(for: item.itemid, valueType: item.value_type?.intValue ?? 0, windowStart: windowStart, windowEnd: windowEnd, serverBaseURL: serverBaseURL, authToken: authToken)

                        series.append(
                            ChartSeries(
                                id: "\(widget.widgetid).\(item.itemid)",
                                name: "\(host.name): \(item.name)",
                                colorHex: Self.shadedColorHex(baseColorHex, index: matchIndex),
                                units: item.units ?? "",
                                fillOpacity: fillOpacity,
                                points: points
                            )
                        )
                        matchIndex += 1
                    }
                }
            }
        }

        for override in overrides {
            guard let hostName = override["hosts.0"], let itemPattern = override["items.0"] else { continue }

            let hosts = try await zabbixAPIClient.hostsByName(serverBaseURL: serverBaseURL, authToken: authToken, names: [hostName])
            guard let host = hosts.first else { continue }

            let items = try await zabbixAPIClient.itemsMatching(
                serverBaseURL: serverBaseURL,
                authToken: authToken,
                hostIDs: [host.hostid],
                namePattern: itemPattern
            )
            guard let item = items.first else { continue }

            let points = try await recentPoints(for: item.itemid, valueType: item.value_type?.intValue ?? 0, windowStart: windowStart, windowEnd: windowEnd, serverBaseURL: serverBaseURL, authToken: authToken)

            series.append(
                ChartSeries(
                    id: "\(widget.widgetid).\(item.itemid)",
                    name: "\(host.name): \(item.name)",
                    colorHex: override["color"] ?? "3DC9B0",
                    units: item.units ?? "",
                    fillOpacity: Self.fillOpacity(fromTransparencyField: override["transparency"]),
                    points: points
                )
            )
        }

        let window = ChartTimeWindow(start: windowStart, end: windowEnd)
        return series.isEmpty ? .unsupported(rawType: widget.type) : .lineChart(series: series, window: window)
    }

    /// Returns all values for keys like "prefix0", "prefix1", ... in a dataset dictionary, in
    /// ascending numeric order (e.g. "items.0", "items.1" -> their values in index order).
    private static func valuesWithNumberedSuffix(_ group: [String: String], prefix: String) -> [String] {
        group.keys
            .filter { $0.hasPrefix(prefix) }
            .compactMap { key -> (Int, String)? in
                guard let index = Int(key.dropFirst(prefix.count)) else { return nil }
                return (index, key)
            }
            .sorted { $0.0 < $1.0 }
            .compactMap { group[$0.1] }
    }

    /// Lightens a base hex color for the Nth item matched by the same dataset pattern, so items
    /// sharing one configured color stay visually distinguishable — approximating Zabbix's own
    /// per-item auto-shading within a multi-item dataset.
    private static func shadedColorHex(_ hex: String, index: Int) -> String {
        guard index > 0, hex.count == 6, let value = UInt32(hex, radix: 16) else { return hex }

        let lightenFactor = min(Double(index) * 0.35, 0.75)
        let r = Double((value >> 16) & 0xFF)
        let g = Double((value >> 8) & 0xFF)
        let b = Double(value & 0xFF)

        func lightened(_ component: Double) -> Int {
            Int(component + (255 - component) * lightenFactor)
        }

        return String(format: "%02X%02X%02X", lightened(r), lightened(g), lightened(b))
    }

    /// Converts a dataset's "transparency" field (0-10, Zabbix's own scale where higher means
    /// MORE fill, despite the name) into a 0...1 opacity for the area drawn under a chart line.
    /// Most datasets never set this field explicitly, but Zabbix still renders its default
    /// (5, a medium fill) rather than no fill at all, which is what made the real graphs look
    /// like layered, shaded regions instead of bare lines.
    private static func fillOpacity(fromTransparencyField value: String?) -> Double {
        let transparency = value.flatMap(Int.init) ?? 5
        return Double(min(max(transparency, 0), 10)) / 10.0
    }

    // MARK: - Classic graph

    /// The "graphid" field name is Zabbix's standard convention for referencing a Graph object, not
    /// yet verified against a live example (no dashboard using the classic "graph" widget type was
    /// available to check against).
    private func resolveClassicGraph(
        _ widget: ZabbixWidget,
        serverBaseURL: URL,
        authToken: String
    ) async throws -> DashboardWidgetKind {
        guard let graphID = Self.fieldValue(widget.fields, name: "graphid") else {
            return .unsupported(rawType: widget.type)
        }

        let graphs = try await zabbixAPIClient.graphs(serverBaseURL: serverBaseURL, authToken: authToken, graphIDs: [graphID])
        guard let graph = graphs.first, !graph.gitems.isEmpty else {
            return .unsupported(rawType: widget.type)
        }

        let items = try await zabbixAPIClient.items(serverBaseURL: serverBaseURL, authToken: authToken, itemIDs: graph.gitems.map(\.itemid))
        let itemsByID = Dictionary(uniqueKeysWithValues: items.map { ($0.itemid, $0) })

        let (windowStart, windowEnd) = Self.timePeriod(from: widget.fields)
        var series: [ChartSeries] = []
        for gitem in graph.gitems {
            guard let item = itemsByID[gitem.itemid] else { continue }

            let points = try await recentPoints(for: item.itemid, valueType: item.value_type?.intValue ?? 0, windowStart: windowStart, windowEnd: windowEnd, serverBaseURL: serverBaseURL, authToken: authToken)

            series.append(ChartSeries(id: "\(widget.widgetid).\(item.itemid)", name: item.name, colorHex: gitem.color, units: item.units ?? "", fillOpacity: 0.5, points: points))
        }

        let window = ChartTimeWindow(start: windowStart, end: windowEnd)
        return series.isEmpty ? .unsupported(rawType: widget.type) : .lineChart(series: series, window: window)
    }

    // MARK: - Pie chart

    /// Reuses the same "ds.N.*" dataset fields as svggraph (Zabbix's newer chart widgets share the
    /// dataset concept). Each dataset can match many items via patterns; every matched item becomes
    /// its own slice — so a wildcard `*` produces one slice per item and the proportions are correct
    /// — unless `dataset_aggregation` collapses the dataset into a single combined slice. Each
    /// item's value is aggregated over the widget's `time_period` when `aggregate_function` is set,
    /// rather than its instantaneous last sample.
    private func resolvePieChart(
        _ widget: ZabbixWidget,
        serverBaseURL: URL,
        authToken: String
    ) async throws -> DashboardWidgetKind {
        let datasets = Self.indexedFieldGroups(widget.fields, prefix: "ds")
        guard !datasets.isEmpty else {
            return .unsupported(rawType: widget.type)
        }

        let (windowStart, windowEnd) = Self.timePeriod(from: widget.fields)
        var slices: [ChartSlice] = []

        for (datasetIndex, dataset) in datasets.enumerated() {
            let hostNames = Self.valuesWithNumberedSuffix(dataset, prefix: "hosts.")
            let itemPatterns = Self.valuesWithNumberedSuffix(dataset, prefix: "items.")
            guard !hostNames.isEmpty, !itemPatterns.isEmpty else { continue }

            let baseColorHex = dataset["color"] ?? "3DC9B0"
            let aggregateFunction = dataset["aggregate_function"].flatMap(Int.init) ?? 0
            let datasetAggregation = dataset["dataset_aggregation"].flatMap(Int.init) ?? 0

            let hosts = try await zabbixAPIClient.hostsByName(serverBaseURL: serverBaseURL, authToken: authToken, names: hostNames)

            // One (id, label, value) per matched item across every host/pattern in the dataset.
            var matched: [(id: String, label: String, value: Double)] = []
            for host in hosts {
                for itemPattern in itemPatterns {
                    let items = try await zabbixAPIClient.itemsMatching(
                        serverBaseURL: serverBaseURL,
                        authToken: authToken,
                        hostIDs: [host.hostid],
                        namePattern: itemPattern
                    )
                    for item in items {
                        let value: Double?
                        if aggregateFunction > 0 {
                            value = try await aggregatedValue(
                                itemID: item.itemid,
                                valueType: item.value_type?.intValue ?? 0,
                                function: aggregateFunction,
                                from: windowStart,
                                to: windowEnd,
                                serverBaseURL: serverBaseURL,
                                authToken: authToken
                            )
                        } else {
                            value = item.lastvalue.flatMap(Double.init)
                        }
                        guard let value else { continue }
                        matched.append((id: item.itemid, label: "\(host.name): \(item.name)", value: value))
                    }
                }
            }
            guard !matched.isEmpty else { continue }

            if datasetAggregation > 0 {
                // Collapse every matched item into one combined slice for this dataset.
                guard let combined = Self.aggregate(matched.map { (clock: 0, value: $0.value) }, function: datasetAggregation) else { continue }
                slices.append(ChartSlice(id: "\(widget.widgetid).ds\(datasetIndex)", name: matched.first?.label ?? "Data set \(datasetIndex + 1)", colorHex: baseColorHex, value: combined))
            } else {
                // One slice per matched item, shaded so items sharing a dataset color stay distinct.
                for (index, entry) in matched.enumerated() {
                    slices.append(ChartSlice(id: "\(widget.widgetid).\(entry.id)", name: entry.label, colorHex: Self.shadedColorHex(baseColorHex, index: index), value: entry.value))
                }
            }
        }

        return slices.isEmpty ? .unsupported(rawType: widget.type) : .pieChart(slices)
    }

    // MARK: - Shared helpers

    /// Fetches an item's history across the widget's full configured window and reduces it to a
    /// bounded, render-friendly set of points that still spans the whole window.
    ///
    /// The window (not a fixed point count) is what bounds the `history.get` call, so the graph
    /// always covers its configured range rather than the newest slice a small `sortorder: DESC`
    /// limit returns. That mattered because a frequently-sampled item (e.g. WAN bandwidth polled
    /// ~1s) produces far more than the old 6000-point cap in 24h, so the cap silently trimmed the
    /// graph to its most recent ~1.7 hours regardless of the 24h window it was labeled with.
    ///
    /// `bucketedChartPoints` then downsamples for rendering: each time bucket keeps its min and max
    /// (so spikes survive, matching Zabbix's peak-preserving graph) and each run of empty buckets
    /// becomes a single break, so a period the item reported nothing for renders as a gap.
    /// Fetches an item's history over `[from, to]` and reduces it to a single aggregate value
    /// (min/max/avg/count/sum/first/last), for widgets that display an aggregate rather than the
    /// last sample. Returns nil when the item has no data in the window.
    private func aggregatedValue(
        itemID: String,
        valueType: Int,
        function: Int,
        from: Date,
        to: Date,
        serverBaseURL: URL,
        authToken: String
    ) async throws -> Double? {
        let values = try await zabbixAPIClient.history(
            serverBaseURL: serverBaseURL,
            authToken: authToken,
            itemID: itemID,
            historyValueType: valueType,
            sinceUnixTime: Int(from.timeIntervalSince1970),
            limit: Self.maxHistoryPointsFetched
        )

        let toEpoch = to.timeIntervalSince1970
        let points = values.compactMap { value -> (clock: Double, value: Double)? in
            guard let doubleValue = Double(value.value), let clock = Double(value.clock), clock <= toEpoch else { return nil }
            return (clock, doubleValue)
        }
        return Self.aggregate(points, function: function)
    }

    private func recentPoints(
        for itemID: String,
        valueType: Int,
        windowStart: Date,
        windowEnd: Date,
        serverBaseURL: URL,
        authToken: String
    ) async throws -> [ChartPoint] {
        let values = try await zabbixAPIClient.history(
            serverBaseURL: serverBaseURL,
            authToken: authToken,
            itemID: itemID,
            historyValueType: valueType,
            sinceUnixTime: Int(windowStart.timeIntervalSince1970),
            limit: Self.maxHistoryPointsFetched
        )

        // history.get returns newest-first; sort ascending so bucketing walks the window in order.
        var points = values.compactMap { value -> (date: Date, value: Double)? in
            guard let doubleValue = Double(value.value), let timestamp = TimeInterval(value.clock) else {
                return nil
            }
            return (Date(timeIntervalSince1970: timestamp), doubleValue)
        }.sorted { $0.date < $1.date }

        // Raw history has a limited retention, so on a long window an item can have history for only
        // its most recent stretch — leaving the rest of the graph blank even though Zabbix's own
        // graph shows it. Fill the older part from trends (hourly min/avg/max, kept far longer),
        // exactly as Zabbix does: use trends for everything before the earliest raw sample.
        let earliestHistory = points.first?.date ?? windowEnd
        if earliestHistory.timeIntervalSince(windowStart) > Self.trendFillMinimumGapSeconds {
            let trendValues = try await zabbixAPIClient.trends(
                serverBaseURL: serverBaseURL,
                authToken: authToken,
                itemID: itemID,
                sinceUnixTime: Int(windowStart.timeIntervalSince1970),
                untilUnixTime: Int(earliestHistory.timeIntervalSince1970)
            )
            let trendPoints = trendValues.compactMap { value -> (date: Date, value: Double)? in
                guard let average = Double(value.value_avg), let timestamp = TimeInterval(value.clock) else {
                    return nil
                }
                return (Date(timeIntervalSince1970: timestamp), average)
            }.filter { $0.date < earliestHistory }

            points = (trendPoints + points).sorted { $0.date < $1.date }
        }

        return Self.bucketedChartPoints(points, itemID: itemID, windowStart: windowStart, windowEnd: windowEnd, bucketCount: Self.chartBucketCount)
    }

    /// Reduces an item's raw, chronological samples to a render-friendly set of points, keeping the
    /// line continuous and only breaking it where the item genuinely reported nothing.
    ///
    /// Two things happen here:
    /// 1. **Downsample when dense.** Only when there are far more samples than we need to draw is the
    ///    window split into time buckets, each contributing its minimum and maximum (peak-preserving,
    ///    so spikes survive). A slowly-sampled item (e.g. a 5-minute ticket count) keeps every point.
    /// 2. **Break only at real gaps.** The break is derived from the data's own median spacing, not a
    ///    fixed bucket size — a nil point is inserted only where consecutive samples are farther apart
    ///    than a few times the normal interval (a genuine outage). The old fixed-bucket break shattered
    ///    any item sampled slower than the bucket width into disconnected dots instead of a line.
    ///
    /// Points are assumed sorted ascending.
    static func bucketedChartPoints(
        _ points: [(date: Date, value: Double)],
        itemID: String,
        windowStart: Date,
        windowEnd: Date,
        bucketCount: Int
    ) -> [ChartPoint] {
        guard !points.isEmpty else { return [] }

        let working: [(date: Date, value: Double)]
        let totalSeconds = windowEnd.timeIntervalSince(windowStart)
        if points.count > 2 * bucketCount, totalSeconds > 0, bucketCount > 0 {
            working = minMaxDownsampled(points, windowStart: windowStart, totalSeconds: totalSeconds, bucketCount: bucketCount)
        } else {
            working = points
        }

        // A line should break only where the item reported nothing for far longer than its own
        // sampling interval — not between every pair of a slowly-sampled item's points. Derive the
        // threshold from the data's median spacing (with a floor) so a 1-second series and a
        // 5-minute series are both drawn continuous, and only a true outage gaps.
        let deltas = zip(working, working.dropFirst()).map { $1.date.timeIntervalSince($0.date) }.filter { $0 > 0 }.sorted()
        let medianDelta = deltas.isEmpty ? 0 : deltas[deltas.count / 2]
        let gapThreshold = max(medianDelta * 3, Self.minimumGapSeconds)

        var result: [ChartPoint] = []
        result.reserveCapacity(working.count + 8)
        for (index, point) in working.enumerated() {
            if index > 0 {
                let gap = point.date.timeIntervalSince(working[index - 1].date)
                if gap > gapThreshold {
                    let breakDate = working[index - 1].date.addingTimeInterval(gap / 2)
                    result.append(ChartPoint(id: "\(itemID).gap.\(index)", date: breakDate, value: nil))
                }
            }
            result.append(ChartPoint(id: "\(itemID).\(index)", date: point.date, value: point.value))
        }
        return result
    }

    /// Buckets dense samples into `bucketCount` time buckets, emitting each non-empty bucket's min
    /// and max (in chronological order, with their original timestamps). Empty buckets emit nothing —
    /// gap breaks are decided by the caller from the data's spacing, not bucket emptiness.
    private static func minMaxDownsampled(
        _ points: [(date: Date, value: Double)],
        windowStart: Date,
        totalSeconds: TimeInterval,
        bucketCount: Int
    ) -> [(date: Date, value: Double)] {
        let bucketSeconds = totalSeconds / Double(bucketCount)
        var buckets: [[(date: Date, value: Double)]] = Array(repeating: [], count: bucketCount)
        for point in points {
            let offset = point.date.timeIntervalSince(windowStart)
            guard offset >= 0, offset <= totalSeconds else { continue }
            let index = min(Int(offset / bucketSeconds), bucketCount - 1)
            buckets[index].append(point)
        }

        var result: [(date: Date, value: Double)] = []
        result.reserveCapacity(bucketCount * 2)
        for bucket in buckets {
            guard let minPoint = bucket.min(by: { $0.value < $1.value }),
                  let maxPoint = bucket.max(by: { $0.value < $1.value }) else { continue }
            let ordered = minPoint.date <= maxPoint.date ? [minPoint, maxPoint] : [maxPoint, minPoint]
            result.append(ordered[0])
            if ordered[1].date != ordered[0].date || ordered[1].value != ordered[0].value {
                result.append(ordered[1])
            }
        }
        return result
    }

    /// A graph widget with no "time_period.*" fields at all is configured to use "Dashboard" as
    /// its time-period source — Zabbix's own frontend then falls back to its global default of
    /// "Last 1 hour" (the same default used across the product, e.g. the item history page) when
    /// the dashboard has no separate time-filter widget setting it to something else. Verified
    /// live: 5 widgets across 2 dashboards ("FreePBX Call Graph", "Data Center Temperature", etc.)
    /// have no time_period fields and neither dashboard has a time-filter widget, so this is what
    /// Zabbix itself would show for them, not an arbitrary placeholder.
    private static let defaultHistoryWindowSeconds = 3600

    /// Upper bound on raw history rows fetched per item, a safety net against a pathologically
    /// dense item rather than the normal limiter (the time window is). Generous enough to cover a
    /// 24h window for an item sampled roughly every second (~86k points); only a faster-than-~1s
    /// item over a long window is trimmed, and `bucketedChartPoints` still spans whatever returned.
    private static let maxHistoryPointsFetched = 100_000

    /// Number of time buckets a chart's window is downsampled to. Each bucket emits up to two
    /// points (its min and max), so a series draws at most ~2x this many marks regardless of how
    /// many raw samples it has — dense enough to read as continuous on a TV without handing Swift
    /// Charts tens of thousands of marks per series.
    private static let chartBucketCount = 800

    /// How much of a graph's window can be missing raw history before we backfill from trends. Set
    /// to one hour (trends are hourly, so a sub-hour gap isn't worth an extra request), so a graph
    /// whose history covers its whole window skips the trend fetch entirely.
    private static let trendFillMinimumGapSeconds: TimeInterval = 3600

    /// Floor for the "real outage" gap threshold when breaking a chart line. A stretch shorter than
    /// this is never treated as a gap even for a fast-sampled item, so brief collection hiccups
    /// don't fragment the line; longer stretches gap only if they also exceed a few sampling
    /// intervals (see `bucketedChartPoints`).
    private static let minimumGapSeconds: TimeInterval = 900

    /// Resolves a widget's configured time period (`time_period.from`/`time_period.to`) into an
    /// absolute `(start, end)` range. Unlike the old duration-only parser this honors an explicit
    /// `.to` (so a window can end in the past, e.g. "yesterday"), calendar-aligned expressions
    /// ("now/d", "now-1d/d", "now/w"), and every offset unit including months and years.
    ///
    /// A missing bound — or one that references the dashboard's own time filter rather than an
    /// absolute expression — falls back to Zabbix's global "last 1 hour" default (a kiosk has no
    /// interactive dashboard time control to inherit). `now` is injectable for testing.
    static func timePeriod(from fields: [ZabbixWidgetField], now: Date = Date()) -> (start: Date, end: Date) {
        let end = fieldValue(fields, name: "time_period.to").flatMap { relativeTime($0, now: now, alignToEnd: true) } ?? now
        let start = fieldValue(fields, name: "time_period.from").flatMap { relativeTime($0, now: now, alignToEnd: false) }
            ?? end.addingTimeInterval(-Double(defaultHistoryWindowSeconds))

        guard start < end else {
            return (now.addingTimeInterval(-Double(defaultHistoryWindowSeconds)), now)
        }
        return (start, end)
    }

    /// Resolves a Zabbix relative-time expression to an absolute `Date`: "now", an offset like
    /// "now-1h" / "now+2d", an alignment like "now/d" (start of today), or both ("now-1d/d", the
    /// start of yesterday). `alignToEnd` selects the *end* of an aligned unit for a `.to` bound so
    /// "now/d" covers the whole current day rather than collapsing to its first instant. Returns
    /// `nil` for anything that isn't a plain relative-time expression (e.g. a dashboard reference).
    static func relativeTime(_ raw: String, now: Date, alignToEnd: Bool) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("now") else { return nil }

        let segments = trimmed.dropFirst(3).split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        var date = now

        let offset = segments[0]
        if !offset.isEmpty {
            guard let shifted = applyRelativeOffset(String(offset), to: date, calendar: calendar) else { return nil }
            date = shifted
        }

        if segments.count == 2, let unit = segments[1].first, let component = calendarComponent(for: unit),
           let interval = calendar.dateInterval(of: component, for: date) {
            date = alignToEnd ? interval.end : interval.start
        }

        return date
    }

    /// Applies a signed relative offset like "-1h", "+2d", "-1M" to a date via the calendar.
    private static func applyRelativeOffset(_ raw: String, to date: Date, calendar: Calendar) -> Date? {
        guard let sign = raw.first, sign == "-" || sign == "+", let unit = raw.last,
              let component = calendarComponent(for: unit),
              let magnitude = Int(raw.dropFirst().dropLast()) else {
            return nil
        }
        return calendar.date(byAdding: component, value: (sign == "-" ? -1 : 1) * magnitude, to: date)
    }

    /// Maps Zabbix's relative-time unit letters to calendar components (s/m/h/d/w/M/y).
    private static func calendarComponent(for unit: Character) -> Calendar.Component? {
        switch unit {
        case "s": return .second
        case "m": return .minute
        case "h": return .hour
        case "d": return .day
        case "w": return .weekOfYear
        case "M": return .month
        case "y": return .year
        default: return nil
        }
    }

    /// Classifies each host's set of interfaces (already filtered to one type, or unfiltered for
    /// the "Total hosts" row) into available/unavailable/mixed/unknown, matching Zabbix's own
    /// host availability widget: a host with two or more interfaces disagreeing on availability
    /// counts as "mixed" rather than being double-counted.
    private static func hostAvailabilityRow(name: String, interfacesByHost: [[ZabbixHostInterface]]) -> HostInterfaceAvailability {
        var available = 0
        var unavailable = 0
        var mixed = 0
        var unknown = 0

        for interfaces in interfacesByHost where !interfaces.isEmpty {
            let statuses = Set(interfaces.map(\.available.intValue))
            let hasAvailable = statuses.contains(1)
            let hasUnavailable = statuses.contains(2)

            if hasAvailable, hasUnavailable {
                mixed += 1
            } else if hasAvailable {
                available += 1
            } else if hasUnavailable {
                unavailable += 1
            } else {
                unknown += 1
            }
        }

        return HostInterfaceAvailability(interfaceTypeName: name, available: available, unavailable: unavailable, mixed: mixed, unknown: unknown)
    }

    /// Filters problems to those whose host is not in any of `excludedGroupIDs`, matching the
    /// "exclude_groupids" option on the problems and problems-by-severity widgets. Resolves each
    /// problem's trigger → host → host groups in two batched lookups; a problem whose host can't be
    /// resolved is kept (fail-open) rather than silently dropped.
    private func problemsExcludingGroups(
        _ problems: [ZabbixProblemSummary],
        excludedGroupIDs: Set<String>,
        serverBaseURL: URL,
        authToken: String
    ) async throws -> [ZabbixProblemSummary] {
        guard !excludedGroupIDs.isEmpty else { return problems }

        let triggerHosts = try await zabbixAPIClient.triggerHosts(
            serverBaseURL: serverBaseURL,
            authToken: authToken,
            triggerIDs: Array(Set(problems.map(\.objectid)))
        )
        let hostIDByTriggerID = Dictionary(uniqueKeysWithValues: triggerHosts.compactMap { entry in
            entry.hosts.first.map { (entry.triggerid, $0.hostid) }
        })

        let hostIDs = Array(Set(hostIDByTriggerID.values))
        let hostGroups = try await zabbixAPIClient.hostGroups(serverBaseURL: serverBaseURL, authToken: authToken, hostIDs: hostIDs)
        let groupIDsByHostID = Dictionary(uniqueKeysWithValues: hostGroups.map { ($0.hostid, Set($0.hostgroups.map(\.groupid))) })

        return problems.filter { problem in
            guard let hostID = hostIDByTriggerID[problem.objectid] else { return true }
            return groupIDsByHostID[hostID, default: []].isDisjoint(with: excludedGroupIDs)
        }
    }

    /// Resolves host names for a set of trigger identifiers in one batched lookup.
    private func hostNamesByTriggerID(
        _ triggerIDs: [String],
        serverBaseURL: URL,
        authToken: String
    ) async throws -> [String: String] {
        let uniqueTriggerIDs = Array(Set(triggerIDs))
        let triggerHosts = try await zabbixAPIClient.triggerHosts(serverBaseURL: serverBaseURL, authToken: authToken, triggerIDs: uniqueTriggerIDs)
        return Dictionary(uniqueKeysWithValues: triggerHosts.compactMap { entry in
            entry.hosts.first.map { (entry.triggerid, $0.name) }
        })
    }

    /// Resolves each active problem's host ID, dropping problems whose trigger's host can't be
    /// resolved. Shared by widgets that need to correlate problems with hosts (problem hosts,
    /// geomap, network map, host navigator).
    private func activeProblemsWithHostID(
        serverBaseURL: URL,
        authToken: String,
        severities: [Int]? = nil,
        groupIDs: [String]? = nil,
        tags: [ZabbixTagFilter]? = nil,
        evalType: Int? = nil,
        showSuppressed: Bool = false
    ) async throws -> [(problem: ZabbixProblemSummary, hostID: String)] {
        let problems = try await zabbixAPIClient.problems(serverBaseURL: serverBaseURL, authToken: authToken, severities: severities, groupIDs: groupIDs, tags: tags, evalType: evalType, showSuppressed: showSuppressed)
        let triggerIDs = Array(Set(problems.map(\.objectid)))
        let triggerHosts = try await zabbixAPIClient.triggerHosts(serverBaseURL: serverBaseURL, authToken: authToken, triggerIDs: triggerIDs)
        let hostIDByTriggerID = Dictionary(uniqueKeysWithValues: triggerHosts.compactMap { entry in
            entry.hosts.first.map { (entry.triggerid, $0.hostid) }
        })

        return problems.compactMap { problem in
            hostIDByTriggerID[problem.objectid].map { (problem, $0) }
        }
    }

    /// Computes the highest active-problem severity per host.
    private func maxSeverityByHostID(serverBaseURL: URL, authToken: String) async throws -> [String: Int] {
        let resolved = try await activeProblemsWithHostID(serverBaseURL: serverBaseURL, authToken: authToken)
        var result: [String: Int] = [:]
        for entry in resolved {
            result[entry.hostID] = max(result[entry.hostID] ?? 0, entry.problem.severity.intValue)
        }
        return result
    }

    /// Strips unresolved macro placeholders like "{HOST.NAME}" from a map element's configured
    /// label, used as a fallback when the element isn't a host (whose real name is resolved
    /// separately via its host ID).
    private static func cleanedMapLabel(_ label: String) -> String {
        let withoutNewlines = label.replacingOccurrences(of: "\r\n", with: " ").trimmingCharacters(in: .whitespaces)
        guard let regex = try? NSRegularExpression(pattern: "\\{[^}]*\\}") else {
            return withoutNewlines
        }
        let range = NSRange(withoutNewlines.startIndex..., in: withoutNewlines)
        return regex.stringByReplacingMatches(in: withoutNewlines, range: range, withTemplate: "")
            .trimmingCharacters(in: .whitespaces)
    }

    private static func interfaceTypeName(_ type: Int) -> String {
        switch type {
        case 1: "Zabbix Agent"
        case 2: "SNMP"
        case 3: "IPMI"
        case 4: "JMX"
        default: "Interface Type \(type)"
        }
    }

    /// Zabbix's own default widget title, shown for a widget with no custom name set — matches
    /// what the Zabbix frontend itself displays, not a capitalized version of the internal API
    /// type string (e.g. "Host availability", not "Hostavail").
    static func defaultTitle(forWidgetType type: String) -> String {
        switch type {
        case "actionlog": "Action log"
        case "clock": "Clock"
        case "dataover": "Data overview"
        case "discovery": "Discovery status"
        case "favgraphs": "Favorite graphs"
        case "favmaps": "Favorite maps"
        case "gauge": "Gauge"
        case "geomap": "Geomap"
        case "graph": "Graph (classic)"
        case "svggraph": "Graph"
        case "graphprototype": "Graph prototype"
        case "honeycomb": "Honeycomb"
        case "hostavail": "Host availability"
        case "hostnavigator": "Host navigator"
        case "item": "Item value"
        case "itemhistory": "Item history"
        case "itemnavigator": "Item navigator"
        case "map": "Map"
        case "navtree": "Map navigation tree"
        case "piechart": "Pie chart"
        case "problemhosts": "Problem hosts"
        case "problems": "Problems"
        case "problemsbysv": "Problems by severity"
        case "slareport": "SLA report"
        case "systeminfo": "System information"
        case "tophosts": "Top hosts"
        case "toptriggers": "Top triggers"
        case "trigover": "Trigger overview"
        case "url": "URL"
        case "web": "Web monitoring"
        default: type.capitalized
        }
    }

    /// Computes a Zabbix aggregate over an item's history points for the item-value/top-hosts
    /// aggregation. `function`: 1 min, 2 max, 3 avg, 4 count, 5 sum, 6 first (earliest), 7 last
    /// (latest). Returns nil for no data or an unknown/none function.
    static func aggregate(_ points: [(clock: Double, value: Double)], function: Int) -> Double? {
        guard !points.isEmpty else { return nil }
        let values = points.map(\.value)
        switch function {
        case 1: return values.min()
        case 2: return values.max()
        case 3: return values.reduce(0, +) / Double(values.count)
        case 4: return Double(values.count)
        case 5: return values.reduce(0, +)
        case 6: return points.min(by: { $0.clock < $1.clock })?.value
        case 7: return points.max(by: { $0.clock < $1.clock })?.value
        default: return nil
        }
    }

    /// The display string for an item reading, applying its value map when it has one: "Up (1)"
    /// rather than a bare "1", matching how the item-value and gauge widgets render. Falls back to
    /// the raw value (or an em dash when absent) so unmapped items are unchanged.
    static func mappedItemValue(rawValue: String?, valueMap: ZabbixValueMap?) -> String {
        guard let raw = rawValue else { return "\u{2014}" }
        if let mapped = valueMap?.mappedText(for: raw) {
            return "\(mapped) (\(raw))"
        }
        return raw
    }

    /// Returns the value of a scalar widget field, e.g. "min" or "show_lines".
    static func fieldValue(_ fields: [ZabbixWidgetField], name: String) -> String? {
        fields.first { $0.name == name }?.value
    }

    /// Zabbix's default dashboard widget refresh rate, applied when a widget is left at "Default"
    /// in its refresh-interval dropdown. Verified against Zabbix's own UI, where "1 minute" is the
    /// bolded default for standard widgets. (A couple of status-style widgets default to 120s, but
    /// those always carry an explicit "rf_rate" field, so they never fall through to this value.)
    static let defaultRefreshIntervalSeconds = 60

    /// The slowest refresh this app will apply, used for a widget the admin explicitly set to
    /// Zabbix's "No refresh". That option means "never auto-refresh" in the Zabbix frontend, where
    /// a person can refresh the browser at will — but this app targets an unattended wall display
    /// with no one at the remote, so "never" would leave the widget frozen on its launch-time
    /// snapshot for as long as the Apple TV stays on. Instead the widget still updates, just at the
    /// longest standard Zabbix interval (15 minutes), honoring the admin's "this changes rarely"
    /// intent without hammering the API or ever going permanently stale.
    static let maximumRefreshIntervalSeconds = 900

    /// Returns how often to re-fetch a widget's data, in seconds — always a positive interval,
    /// since an unattended display should never show a widget that stops updating. The value comes
    /// from the widget's own Zabbix "rf_rate" field, verified against a live server (e.g. 30s on a
    /// "problems" widget, 120s on "systeminfo"):
    ///
    /// - An explicit positive "rf_rate" is used as-is.
    /// - An absent field means the widget is at "Default" in Zabbix's dropdown (Zabbix stores no
    ///   field in that case) → `defaultRefreshIntervalSeconds`. Treating absent as "never" is what
    ///   left every default-rate widget (item value, gauge, etc.) frozen on its opening snapshot.
    /// - An explicit "0" is Zabbix's "No refresh" → `maximumRefreshIntervalSeconds` rather than
    ///   never, for the unattended-display reason documented on that constant.
    static func refreshIntervalSeconds(from fields: [ZabbixWidgetField]) -> Int {
        guard let rate = fieldValue(fields, name: "rf_rate").flatMap(Int.init) else {
            return defaultRefreshIntervalSeconds
        }
        return rate > 0 ? rate : maximumRefreshIntervalSeconds
    }

    /// Returns all values for a dot-indexed widget field array, e.g. "groupids.0", "groupids.1".
    static func indexedValues(_ fields: [ZabbixWidgetField], name: String) -> [String] {
        fields.filter { $0.name == name || $0.name.hasPrefix("\(name).") }.map(\.value)
    }

    /// Returns the first value for a dot-indexed widget field array.
    static func firstIndexedValue(_ fields: [ZabbixWidgetField], name: String) -> String? {
        indexedValues(fields, name: name).first
    }

    /// Groups widget fields named like "prefix.0.suffix" into one dictionary per index, e.g.
    /// "thresholds.0.color" and "thresholds.0.threshold" become `["color": ..., "threshold": ...]`
    /// at index 0. Indices are returned in ascending order.
    static func indexedFieldGroups(_ fields: [ZabbixWidgetField], prefix: String) -> [[String: String]] {
        var groupsByIndex: [Int: [String: String]] = [:]
        let namePrefix = "\(prefix)."

        for field in fields where field.name.hasPrefix(namePrefix) {
            let remainder = field.name.dropFirst(namePrefix.count)
            let parts = remainder.split(separator: ".", maxSplits: 1)
            guard parts.count == 2, let index = Int(parts[0]) else { continue }
            groupsByIndex[index, default: [:]][String(parts[1])] = field.value
        }

        return groupsByIndex.keys.sorted().compactMap { groupsByIndex[$0] }
    }

    /// Reads a widget's tag filter (its `<prefix>.N.tag` / `.operator` / `.value` fields) into API
    /// tag filters. Entries with no tag name are dropped; a missing operator defaults to 0
    /// (Contains), matching Zabbix. Returns an empty array when the widget has no tag filter, so
    /// callers can pass it straight through and leave an unfiltered query unchanged. `prefix`
    /// defaults to "tags" (problem/item widgets); host-oriented widgets store theirs as "host_tags".
    static func tagFilters(from fields: [ZabbixWidgetField], prefix: String = "tags") -> [ZabbixTagFilter] {
        indexedFieldGroups(fields, prefix: prefix).compactMap { group in
            guard let tag = group["tag"], !tag.isEmpty else { return nil }
            return ZabbixTagFilter(tag: tag, value: group["value"] ?? "", operator: group["operator"].flatMap(Int.init) ?? 0)
        }
    }

    /// The widget's tag evaluation type: 0 = And/Or, 2 = Or. `nil` when unset (the API then applies
    /// its And/Or default). `field` defaults to "evaltype"; host widgets use "host_tags_evaltype".
    static func tagEvalType(from fields: [ZabbixWidgetField], field: String = "evaltype") -> Int? {
        fieldValue(fields, name: field).flatMap(Int.init)
    }

    /// Resolves a widget's positive host-group scope (`groupids.N`) into the full set of group IDs
    /// to pass to `groupids`-supporting API calls — **including nested subgroups**, which Zabbix's
    /// own frontend expands before querying but the API does not. Returns `nil` when the widget has
    /// no group scope (meaning "all groups"), so callers pass it straight through.
    ///
    /// Nested expansion resolves the selected groups' names, then adds every visible group whose
    /// name equals one of them or begins with "<name>/". Falls back to the literal selected IDs if
    /// the name lookup fails, so scoping never silently widens to the whole server.
    func scopedGroupIDs(from widget: ZabbixWidget, serverBaseURL: URL, authToken: String) async throws -> [String]? {
        let selected = Set(Self.indexedValues(widget.fields, name: "groupids"))
        guard !selected.isEmpty else { return nil }

        let allGroups = (try? await zabbixAPIClient.hostGroupNames(serverBaseURL: serverBaseURL, authToken: authToken, groupIDs: nil)) ?? []
        let selectedNames = allGroups.filter { selected.contains($0.groupid) }.map(\.name)
        guard !selectedNames.isEmpty else { return Array(selected) }

        var expanded = selected
        for group in allGroups where selectedNames.contains(where: { group.name == $0 || group.name.hasPrefix("\($0)/") }) {
            expanded.insert(group.groupid)
        }
        return Array(expanded)
    }
}
