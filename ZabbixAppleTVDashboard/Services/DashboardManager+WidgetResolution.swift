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
            pendingDefaultTitle = nil
            let kind = try await resolveWidgetKind(widget, serverBaseURL: serverBaseURL, authToken: authToken)
            // A custom widget name always wins; otherwise a resolver-provided data-driven title
            // (Zabbix's "HOST: item name" style defaults), then the widget-type fallback.
            let dataDrivenTitle = pendingDefaultTitle
            pendingDefaultTitle = nil
            result.append(
                RenderableDashboardWidget(
                    id: widget.widgetid,
                    title: widget.name?.isEmpty == false ? widget.name! : (dataDrivenTitle ?? Self.defaultTitle(forWidgetType: widget.type)),
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
            let style: ClockStyle = isDigital ? .digital : .analog

            // "time_type": 0 = local, 1 = server, 2 = host. Host time reads the selected host's own
            // clock from its system.localtime item; local/server fall through to the device clock
            // (optionally shifted by the configured timezone).
            let timeType = Self.fieldValue(widget.fields, name: "time_type").flatMap(Int.init) ?? 0
            let timeZoneIdentifier = Self.clockTimeZoneIdentifier(from: widget.fields)

            var hostTimeOffset: TimeInterval?
            var clockHostName: String?
            if timeType == 2, let itemID = Self.firstIndexedValue(widget.fields, name: "itemid") {
                let items = try await zabbixAPIClient.items(serverBaseURL: serverBaseURL, authToken: authToken, itemIDs: [itemID])
                hostTimeOffset = Self.hostTimeOffset(lastValue: items.first?.lastvalue, lastClock: items.first?.lastclock)
                clockHostName = items.first?.hosts?.first?.name
            }

            // Zabbix's default clock header names the time source: "Local", "Server", or the host.
            pendingDefaultTitle = timeType == 2 ? (clockHostName ?? "Host") : (timeType == 1 ? "Server" : "Local")
            return .clock(ClockConfiguration(style: style, timeZoneIdentifier: timeZoneIdentifier, hostTimeOffset: hostTimeOffset))

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
                showSuppressed: Self.fieldValue(widget.fields, name: "show_suppressed") == "1",
                acknowledged: Self.problemsAcknowledgedFilter(from: widget.fields)
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

            // "show_tags" caps how many event tags are shown per problem (Zabbix's default is 3);
            // 0 hides them.
            let showTags = Self.fieldValue(widget.fields, name: "show_tags").flatMap(Int.init) ?? 3

            return .problems(
                visibleProblems.prefix(showLines).map { problem in
                    DashboardProblem(
                        id: problem.eventid,
                        name: problem.name,
                        severity: problem.severity.intValue,
                        host: hostByTriggerID[problem.objectid]?.name,
                        since: Date(timeIntervalSince1970: TimeInterval(problem.clock) ?? 0),
                        tags: showTags > 0 ? (problem.tags ?? []).prefix(showTags).map { ProblemTag(tag: $0.tag, value: $0.value) } : []
                    )
                }
            )

        case "item":
            guard let itemID = Self.firstIndexedValue(widget.fields, name: "itemid") else {
                return .unsupported(rawType: widget.type)
            }

            let items = try await zabbixAPIClient.items(serverBaseURL: serverBaseURL, authToken: authToken, itemIDs: [itemID])
            guard let item = items.first else {
                // The configured item resolved to nothing — deleted, or not visible to this account.
                return .referencedObjectUnavailable
            }

            // When the widget aggregates over a time period (min/max/avg/count/sum/first/last),
            // show that computed value rather than the instantaneous last sample. A value map and
            // the up/down trend only apply to the raw last value, so they're suppressed when
            // aggregating.
            let aggregateFunction = Self.fieldValue(widget.fields, name: "aggregate_function").flatMap(Int.init) ?? 0
            let displayValue: String
            let mappedText: String?
            let numericValue: Double?
            if aggregateFunction > 0 {
                let (from, to) = Self.timePeriod(from: widget.fields)
                let aggregated = try await aggregatedValue(itemID: item.itemid, valueType: item.value_type?.intValue ?? 0, function: aggregateFunction, from: from, to: to, serverBaseURL: serverBaseURL, authToken: authToken)
                displayValue = aggregated.map { String($0) } ?? "\u{2014}"
                mappedText = nil
                numericValue = aggregated
            } else {
                displayValue = item.lastvalue ?? "\u{2014}"
                mappedText = item.lastvalue.flatMap { item.valuemap?.valueMap?.mappedText(for: $0) }
                numericValue = item.lastvalue.flatMap(Double.init)
            }

            // A value crossing a configured threshold repaints the background with that band's
            // color (Zabbix's alert color); the static `bg_color` is the fallback when no threshold
            // is met or none are set.
            let backgroundColorHex = Self.thresholdColorHex(for: numericValue, fields: widget.fields)
                ?? Self.fieldValue(widget.fields, name: "bg_color")

            // The change indicator is a "show" flag (8), on by default like the widget's other
            // elements — Zabbix draws it with theme-default green/red when no custom up_color/
            // down_color is configured (verified live: the QA widget has no color fields yet shows
            // a green ▲ / red ▼ beside the value). Requiring the color fields hid it entirely.
            let showFlags = Set(Self.indexedValues(widget.fields, name: "show").compactMap(Int.init))
            let effectiveShow: Set<Int> = showFlags.isEmpty ? [1, 2, 4, 8] : showFlags

            var trend: ItemValueTrend?
            if effectiveShow.contains(8), aggregateFunction == 0, let lastvalue = item.lastvalue.flatMap(Double.init), let prevvalue = item.prevvalue.flatMap(Double.init) {
                let upColor = Self.fieldValue(widget.fields, name: "up_color").flatMap { $0.isEmpty ? nil : $0 } ?? "59DB8F"
                let downColor = Self.fieldValue(widget.fields, name: "down_color").flatMap { $0.isEmpty ? nil : $0 } ?? "E45959"
                if lastvalue > prevvalue {
                    trend = .up(colorHex: upColor)
                } else if lastvalue < prevvalue {
                    trend = .down(colorHex: downColor)
                }
            }

            // Units display honors the widget's overrides: `units` replaces the item's own units,
            // `units_show` (default on) toggles whether any unit is shown, and `decimal_places`
            // (default 2) sets the precision. Passing an empty unit string suppresses the suffix.
            let showUnits = Self.fieldValue(widget.fields, name: "units_show") != "0"
            let unitsOverride = Self.fieldValue(widget.fields, name: "units")
            let resolvedUnits = showUnits ? (unitsOverride?.isEmpty == false ? unitsOverride! : (item.units ?? "")) : ""
            let decimalPlaces = Self.fieldValue(widget.fields, name: "decimal_places").flatMap(Int.init) ?? 2

            // The widget's `description` is a label template with macros (default "{ITEM.NAME}",
            // which reproduces the previous behavior); expand it into the shown label.
            let label = Self.expandLabel(
                template: Self.fieldValue(widget.fields, name: "description"),
                item: item,
                decimalPlaces: decimalPlaces
            )

            // Zabbix's default item-value header is "HOST: item name".
            pendingDefaultTitle = Self.hostPrefixedTitle(host: item.hosts?.first?.name, name: item.name)
            return .itemValue(
                name: label,
                value: displayValue,
                units: resolvedUnits,
                decimalPlaces: decimalPlaces,
                backgroundColorHex: backgroundColorHex,
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
                showSuppressed: Self.fieldValue(widget.fields, name: "show_suppressed") == "1",
                acknowledged: Self.severityAcknowledgedFilter(from: widget.fields)
            )
            let problems = try await problemsExcludingGroups(allProblems, excludedGroupIDs: excludedGroupIDs, serverBaseURL: serverBaseURL, authToken: authToken)

            // "show_type" ("Show"): 0 / absent = Host groups (the default — a table of groups ×
            // severities, verified against the live widget: a config with show_type 0 renders the
            // groups table in Zabbix), 1 = Totals (the single row of severity blocks). The earlier
            // mapping had these swapped. Groups mode resolves each problem's host and counts it in
            // every group that host belongs to.
            if Self.fieldValue(widget.fields, name: "show_type").flatMap(Int.init) != 1 {
                let triggerHosts = try await zabbixAPIClient.triggerHosts(serverBaseURL: serverBaseURL, authToken: authToken, triggerIDs: Array(Set(problems.map(\.objectid))))
                let hostIDByTriggerID = Dictionary(uniqueKeysWithValues: triggerHosts.compactMap { entry in entry.hosts.first.map { (entry.triggerid, $0.hostid) } })
                let hostGroups = try await zabbixAPIClient.hostGroups(serverBaseURL: serverBaseURL, authToken: authToken, hostIDs: Array(Set(hostIDByTriggerID.values)))
                let groupsByHostID = Dictionary(uniqueKeysWithValues: hostGroups.map { ($0.hostid, $0.hostgroups) })

                var byGroup: [String: (name: String, counts: [Int])] = [:]
                for problem in problems {
                    guard let hostID = hostIDByTriggerID[problem.objectid], let groups = groupsByHostID[hostID] else { continue }
                    let severity = min(max(problem.severity.intValue, 0), 5)
                    for group in groups {
                        var entry = byGroup[group.groupid] ?? (name: group.name, counts: Array(repeating: 0, count: 6))
                        entry.counts[severity] += 1
                        byGroup[group.groupid] = entry
                    }
                }

                // Zabbix lists every in-scope group that actually contains hosts — including ones
                // with no problems — unless "hide_empty_groups" is on, and sorts the table by group
                // name. `withHosts` keeps host-less groups (e.g. template-organization groups) out,
                // as Zabbix's own widget does.
                if Self.fieldValue(widget.fields, name: "hide_empty_groups") != "1" {
                    let scoped = try await scopedGroupIDs(from: widget, serverBaseURL: serverBaseURL, authToken: authToken)
                    let visibleGroups = (try? await zabbixAPIClient.hostGroupNames(serverBaseURL: serverBaseURL, authToken: authToken, groupIDs: scoped, withHosts: true)) ?? []
                    for group in visibleGroups where byGroup[group.groupid] == nil && !excludedGroupIDs.contains(group.groupid) {
                        byGroup[group.groupid] = (name: group.name, counts: Array(repeating: 0, count: 6))
                    }
                }

                return .problemsByHostGroup(
                    byGroup.map { groupID, entry in
                        HostGroupProblemSummary(id: groupID, groupName: entry.name, countsBySeverity: entry.counts)
                    }.sorted { $0.groupName.localizedCaseInsensitiveCompare($1.groupName) == .orderedAscending }
                )
            }

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
                Self.hostAvailabilityRow(name: "Total Hosts", interfacesByHost: hosts.map(\.interfaces))
            ]

            // "Agent (active)" sits between Total Hosts and the interface rows when the agent type
            // is shown, counting each host's active-check availability (the 7.0 host-level
            // `active_available` field: 1 = available, 2 = unavailable). Status 0 covers both "no
            // active checks" and "not yet known", which the API can't distinguish — those hosts are
            // left uncounted rather than inflating Unknown with every passive-only host (Zabbix's
            // own row counts only hosts that use active checks). Active checks aren't
            // interface-based, so the Mixed column renders Zabbix's "-".
            if requestedTypes.contains(1) {
                let statuses = hosts.compactMap { $0.active_available?.intValue }
                rows.append(HostInterfaceAvailability(
                    interfaceTypeName: "Agent (active)",
                    available: statuses.filter { $0 == 1 }.count,
                    unavailable: statuses.filter { $0 == 2 }.count,
                    mixed: 0,
                    unknown: 0,
                    isActiveChecksRow: true
                ))
            }

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
            return try await resolveSystemInformation(widget, serverBaseURL: serverBaseURL, authToken: authToken)

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
            return try await resolveMapNavigationTree(widget, serverBaseURL: serverBaseURL, authToken: authToken)

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
        guard let item = items.first else {
            // The configured item resolved to nothing — deleted, or not visible to this account.
            return .referencedObjectUnavailable
        }
        guard let value = item.lastvalue.flatMap(Double.init) else {
            return .unsupported(rawType: widget.type)
        }

        let minValue = Self.fieldValue(widget.fields, name: "min").flatMap(Double.init) ?? 0
        let maxValue = Self.fieldValue(widget.fields, name: "max").flatMap(Double.init) ?? 100

        // Same unit/precision overrides as the item-value widget: `units` replaces the item's own
        // units, `units_show` (default on) toggles the suffix, `decimal_places` (default 2) sets the
        // center value's precision.
        let showUnits = Self.fieldValue(widget.fields, name: "units_show") != "0"
        let unitsOverride = Self.fieldValue(widget.fields, name: "units")
        let resolvedUnits = showUnits ? (unitsOverride?.isEmpty == false ? unitsOverride! : (item.units ?? "")) : ""
        let decimalPlaces = Self.fieldValue(widget.fields, name: "decimal_places").flatMap(Int.init) ?? 2

        let thresholds = Self.indexedFieldGroups(widget.fields, prefix: "thresholds")
            .compactMap { group -> GaugeThreshold? in
                guard let thresholdValue = group["threshold"].flatMap(Double.init), let color = group["color"] else {
                    return nil
                }
                return GaugeThreshold(value: thresholdValue, colorHex: color)
            }
            .sorted { $0.value < $1.value }

        let label = Self.expandLabel(
            template: Self.fieldValue(widget.fields, name: "description"),
            item: item,
            decimalPlaces: decimalPlaces
        )

        // "Show" checkboxes (verified against the live edit form): 1 = Description, 2 = Value,
        // 3 = Needle, 4 = Value arc, 5 = Scale. An absent field means a freshly-created widget's
        // defaults — everything but the needle.
        let showFlags = Set(Self.indexedValues(widget.fields, name: "show").compactMap(Int.init))
        let effectiveShow = showFlags.isEmpty ? [1, 2, 4, 5] : showFlags

        // Zabbix's default gauge header is "HOST: item name".
        pendingDefaultTitle = Self.hostPrefixedTitle(host: item.hosts?.first?.name, name: item.name)
        return .gauge(
            GaugeReading(
                name: label,
                value: value,
                minValue: minValue,
                maxValue: maxValue,
                units: resolvedUnits,
                decimalPlaces: decimalPlaces,
                thresholds: thresholds,
                fixedArcColorHex: Self.fieldValue(widget.fields, name: "value_arc_color"),
                mappedText: item.lastvalue.flatMap { item.valuemap?.valueMap?.mappedText(for: $0) },
                showDescription: effectiveShow.contains(1),
                showValue: effectiveShow.contains(2),
                showNeedle: effectiveShow.contains(3),
                showValueArc: effectiveShow.contains(4),
                showScale: effectiveShow.contains(5),
                needleColorHex: Self.fieldValue(widget.fields, name: "needle_color").flatMap { $0.isEmpty ? nil : $0 },
                angleDegrees: Self.fieldValue(widget.fields, name: "angle").flatMap(Double.init) ?? 180,
                valueColorHex: Self.fieldValue(widget.fields, name: "value_color").flatMap { $0.isEmpty ? nil : $0 },
                descriptionColorHex: Self.fieldValue(widget.fields, name: "desc_color").flatMap { $0.isEmpty ? nil : $0 },
                emptyColorHex: Self.fieldValue(widget.fields, name: "empty_color").flatMap { $0.isEmpty ? nil : $0 }
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

        let decimalPlaces = Self.fieldValue(widget.fields, name: "decimal_places").flatMap(Int.init) ?? 2
        // Each cell shows two label templates; Zabbix's defaults are the host name (primary) and the
        // last value (secondary) when the widget doesn't configure them.
        let primaryTemplate = Self.fieldValue(widget.fields, name: "primary_label").flatMap { $0.isEmpty ? nil : $0 } ?? "{HOST.NAME}"
        let secondaryTemplate = Self.fieldValue(widget.fields, name: "secondary_label").flatMap { $0.isEmpty ? nil : $0 } ?? "{ITEM.LASTVALUE}"

        return .honeycomb(
            items.prefix(60).map { item in
                // Each cell is tinted by the threshold band its reading meets — the same value-driven
                // coloring Zabbix's honeycomb applies — using the shared thresholds.N resolver.
                let cellColor = Self.thresholdColorHex(for: item.lastvalue.flatMap(Double.init), fields: widget.fields)
                let macros = Self.itemLabelMacros(
                    itemName: item.name,
                    hostName: item.hosts.first?.name ?? "",
                    lastValue: item.lastvalue,
                    units: item.units ?? "",
                    valueMap: item.valuemap?.valueMap,
                    decimalPlaces: decimalPlaces
                )
                return HoneycombCell(
                    id: item.itemid,
                    primaryLabel: Self.expandMacros(primaryTemplate, macros),
                    secondaryLabel: Self.expandMacros(secondaryTemplate, macros),
                    backgroundColorHex: cellColor
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
            var hasItemColumn = false
            var hasItemData = false
            for (index, column) in columnGroups.enumerated() {
                let cell = try await topHostsColumnValue(column, host: host, from: from, to: to, serverBaseURL: serverBaseURL, authToken: authToken)
                values.append(cell.display ?? "")
                if cell.isItemColumn {
                    hasItemColumn = true
                    if cell.display != nil { hasItemData = true }
                }
                if index == sortColumnIndex { sortValue = cell.numeric }
            }
            // Zabbix drops a host from the table entirely when none of its item columns have data
            // in the widget's time period (verified live: a host whose only reading was a stale
            // "0 B" outside the window is simply absent, not shown as "0.00 B" or an empty row).
            guard !hasItemColumn || hasItemData else { continue }
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
    /// otherwise they show the value-mapped last reading. A nil `display` means an item column had
    /// no data within the widget's time period — the caller uses that to drop dataless hosts the
    /// way Zabbix does.
    private func topHostsColumnValue(
        _ column: [String: String],
        host: ZabbixHostListEntry,
        from: Date,
        to: Date,
        serverBaseURL: URL,
        authToken: String
    ) async throws -> (display: String?, numeric: Double?, isItemColumn: Bool) {
        // A text column is a fixed label with nothing to rank by.
        if let text = column["text"], !text.isEmpty, (column["item"] ?? "").isEmpty {
            return (text, nil, false)
        }

        guard let itemPattern = column["item"], !itemPattern.isEmpty else {
            return (host.name, nil, false)
        }

        let items = try await zabbixAPIClient.itemsMatching(
            serverBaseURL: serverBaseURL,
            authToken: authToken,
            hostIDs: [host.hostid],
            namePattern: itemPattern
        )
        guard let item = items.first else { return (nil, nil, true) }

        // Per-column display precision; units come from the item (or the column's units override).
        let decimalPlaces = column["decimal_places"].flatMap(Int.init) ?? 2
        let units = column["units"]?.isEmpty == false ? column["units"]! : (item.units ?? "")

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
            let display = aggregated.map { ZabbixValueFormatting.formatItemValue($0, units: units, decimalPlaces: decimalPlaces) }
            return (display, aggregated, true)
        }

        // Zabbix's non-aggregated column is still scoped to the widget's time period: a last
        // reading recorded before the window (a stale value from a host that stopped reporting)
        // counts as no data, exactly like the frontend, which omitted such a host from the table.
        if let lastClock = item.lastclock.flatMap(TimeInterval.init),
           lastClock < from.timeIntervalSince1970 || lastClock > to.timeIntervalSince1970 {
            return (nil, nil, true)
        }
        guard let lastvalue = item.lastvalue, !lastvalue.isEmpty else { return (nil, nil, true) }

        let display = Self.formattedItemValue(rawValue: lastvalue, units: units, valueMap: item.valuemap?.valueMap, decimalPlaces: decimalPlaces)
        return (display, Double(lastvalue), true)
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
        // Zabbix's Top triggers ranks triggers by how many times they went into problem state over
        // the widget's time period — a frequency count — not the current problem list sorted by
        // severity. Count problem events per trigger over the window and show the busiest N.
        let limit = Self.fieldValue(widget.fields, name: "show_lines").flatMap(Int.init) ?? 10
        let severities = Self.indexedValues(widget.fields, name: "severities").compactMap(Int.init)
        let (from, to) = Self.timePeriod(from: widget.fields)

        let events = try await zabbixAPIClient.problemEvents(
            serverBaseURL: serverBaseURL,
            authToken: authToken,
            timeFrom: Int(from.timeIntervalSince1970),
            timeTill: Int(to.timeIntervalSince1970),
            severities: severities.isEmpty ? nil : severities,
            groupIDs: try await scopedGroupIDs(from: widget, serverBaseURL: serverBaseURL, authToken: authToken),
            tags: Self.tagFilters(from: widget.fields),
            evalType: Self.tagEvalType(from: widget.fields)
        )

        let ranked = Self.rankTriggersByFrequency(events).prefix(limit)

        let hostByTriggerID = try await hostNamesByTriggerID(
            ranked.map(\.triggerID),
            serverBaseURL: serverBaseURL,
            authToken: authToken
        )

        return .topTriggers(
            ranked.map { trigger in
                DashboardProblem(
                    id: trigger.triggerID,
                    name: trigger.name,
                    severity: trigger.severity,
                    host: hostByTriggerID[trigger.triggerID],
                    since: Date(timeIntervalSince1970: trigger.latest),
                    problemCount: trigger.count
                )
            }
        )
    }

    /// Aggregates problem events into per-trigger frequency counts, ordered busiest-first (ties
    /// broken by worst severity, then most-recent). Each trigger's display name/severity come from
    /// its most recent event and its worst-seen severity respectively.
    static func rankTriggersByFrequency(_ events: [ZabbixEventSummary]) -> [TriggerFrequency] {
        var byTrigger: [String: TriggerFrequency] = [:]
        for event in events {
            let clock = Double(event.clock) ?? 0
            let severity = event.severity.intValue
            if let existing = byTrigger[event.objectid] {
                byTrigger[event.objectid] = TriggerFrequency(
                    triggerID: existing.triggerID,
                    count: existing.count + 1,
                    name: clock > existing.latest ? event.name : existing.name,
                    severity: max(existing.severity, severity),
                    latest: max(existing.latest, clock)
                )
            } else {
                byTrigger[event.objectid] = TriggerFrequency(triggerID: event.objectid, count: 1, name: event.name, severity: severity, latest: clock)
            }
        }
        return byTrigger.values.sorted { lhs, rhs in
            if lhs.count != rhs.count { return lhs.count > rhs.count }
            if lhs.severity != rhs.severity { return lhs.severity > rhs.severity }
            return lhs.latest > rhs.latest
        }
    }

    // MARK: - Trigger overview

    /// How many triggers the overview fetches at most — reaching it means the table is truncated
    /// and gets Zabbix's "Not all results are displayed" note.
    static let triggerOverviewFetchLimit = 100

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
            evalType: Self.tagEvalType(from: widget.fields),
            limit: Self.triggerOverviewFetchLimit
        )

        var rowsByHostID: [String: TriggerOverviewRow] = [:]

        for trigger in triggers {
            guard let host = trigger.hosts.first else { continue }
            // When only PROBLEM-state triggers were fetched, `value` is unrequested, so every
            // trigger here is in problem state; otherwise read the trigger's actual current state.
            let isProblem = showAny ? (trigger.value?.intValue ?? 1) == 1 : true
            let indicator = TriggerIndicator(id: trigger.triggerid, name: trigger.description, severity: trigger.priority.intValue, isProblem: isProblem, hasDependency: trigger.dependencies?.isEmpty == false)

            if let existing = rowsByHostID[host.hostid] {
                rowsByHostID[host.hostid] = TriggerOverviewRow(id: existing.id, hostName: existing.hostName, triggers: existing.triggers + [indicator])
            } else {
                rowsByHostID[host.hostid] = TriggerOverviewRow(id: host.hostid, hostName: host.name, triggers: [indicator])
            }
        }

        // Zabbix sorts the table by host name and appends "Not all results are displayed" when its
        // query hit the fetch limit — both verified against the live widget (hosts ascending,
        // note shown for this dashboard's oversubscribed Apple TV group).
        let sortedRows = rowsByHostID.values.sorted { $0.hostName.localizedStandardCompare($1.hostName) == .orderedAscending }
        return .triggerOverview(sortedRows, truncated: triggers.count >= Self.triggerOverviewFetchLimit)
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

        // "Problem hosts" counts distinct HOSTS with an active problem per group, matching Zabbix's
        // own widget (not the total number of problems). Per group, track each host's WORST severity
        // so the counts can be broken out into per-severity columns while a host still counts once.
        var worstSeverityByGroup: [String: (name: String, worstByHost: [String: Int])] = [:]

        for entry in resolved {
            guard let groups = groupsByHostID[entry.hostID] else { continue }

            for group in groups {
                var summary = worstSeverityByGroup[group.groupid] ?? (name: group.name, worstByHost: [:])
                summary.worstByHost[entry.hostID] = max(summary.worstByHost[entry.hostID] ?? 0, entry.problem.severity.intValue)
                worstSeverityByGroup[group.groupid] = summary
            }
        }

        return .problemsByHostGroup(
            worstSeverityByGroup.map { groupID, summary in
                HostGroupProblemSummary(id: groupID, groupName: summary.name, countsBySeverity: Self.severityCounts(fromWorstSeverities: Array(summary.worstByHost.values)))
            }.sorted { $0.maxSeverity == $1.maxSeverity ? $0.count > $1.count : $0.maxSeverity > $1.maxSeverity }
        )
    }

    /// Groups (key, entry) pairs into ordered sections for a navigator's `group_by`: when not
    /// grouped, all entries fall in a single untitled section; when grouped, they're bucketed by key
    /// in first-seen order (an entry can appear under several keys, e.g. a host in multiple groups).
    static func groupedSections<Entry>(_ pairs: [(key: String, entry: Entry)], grouped: Bool) -> [(title: String, entries: [Entry])] {
        guard grouped else {
            return pairs.isEmpty ? [] : [("", pairs.map(\.entry))]
        }
        var order: [String] = []
        var seen = Set<String>()
        var byKey: [String: [Entry]] = [:]
        for pair in pairs {
            if seen.insert(pair.key).inserted { order.append(pair.key) }
            byKey[pair.key, default: []].append(pair.entry)
        }
        return order.map { ($0, byKey[$0] ?? []) }
    }

    /// Buckets each host's worst severity into a 6-slot per-severity count array (index 0…5),
    /// clamping out-of-range severities into the valid band.
    static func severityCounts(fromWorstSeverities severities: [Int]) -> [Int] {
        var counts = Array(repeating: 0, count: 6)
        for severity in severities {
            counts[min(max(severity, 0), 5)] += 1
        }
        return counts
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

        // A marker's color must reflect only the problems the widget's own filter shows — its
        // severity floor and problem-tag filter — not every problem on the host. The lookup is
        // keyed by host ID, so problems on hosts without a marker simply don't contribute.
        let severities = Self.indexedValues(widget.fields, name: "severities").compactMap(Int.init)
        let severityByHostID = try await maxSeverityByHostID(
            serverBaseURL: serverBaseURL,
            authToken: authToken,
            severities: severities.isEmpty ? nil : severities,
            tags: Self.tagFilters(from: widget.fields),
            evalType: Self.tagEvalType(from: widget.fields)
        )

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

        return .geomap(markers: markers, defaultView: Self.parseGeoMapDefaultView(Self.fieldValue(widget.fields, name: "default_view")))
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
        guard let mapID = Self.fieldValue(widget.fields, name: "sysmapid") else {
            return .unsupported(rawType: widget.type)
        }
        guard let map = try await zabbixAPIClient.networkMap(serverBaseURL: serverBaseURL, authToken: authToken, mapID: mapID) else {
            // The configured map resolved to nothing — deleted, or not visible to this account.
            return .referencedObjectUnavailable
        }

        let backgroundImageData = try await backgroundImageData(forImageID: map.backgroundid, serverBaseURL: serverBaseURL, authToken: authToken)

        let hostIDs = map.selements.compactMap { $0.elementtype.intValue == 0 ? $0.elements.first?.hostid : nil }
        let hosts = try await zabbixAPIClient.hosts(serverBaseURL: serverBaseURL, authToken: authToken, hostIDs: hostIDs.isEmpty ? nil : hostIDs)
        let hostNameByID = Dictionary(uniqueKeysWithValues: hosts.map { ($0.hostid, $0.name) })
        let severityByHostID = try await maxSeverityByHostID(serverBaseURL: serverBaseURL, authToken: authToken)

        // Full active problem list drives both the link overrides (by trigger ID) and the severity
        // of trigger-type map elements (worst severity among the triggers the element references).
        let problems = try await zabbixAPIClient.problems(serverBaseURL: serverBaseURL, authToken: authToken)
        let activeTriggerIDs = Set(problems.map(\.objectid))
        var severityByTriggerID: [String: Int] = [:]
        for problem in problems {
            severityByTriggerID[problem.objectid] = max(severityByTriggerID[problem.objectid] ?? 0, problem.severity.intValue)
        }

        // Host-group elements take the worst severity across the group's hosts. Resolve each
        // referenced group's hosts once (maps rarely carry many group elements).
        let groupElementGroupIDs = Set(map.selements.filter { $0.elementtype.intValue == 3 }.compactMap { $0.elements.first?.groupid })
        var severityByGroupID: [String: Int] = [:]
        for groupID in groupElementGroupIDs {
            let groupHosts = try await zabbixAPIClient.hosts(serverBaseURL: serverBaseURL, authToken: authToken, groupIDs: [groupID], hostIDs: nil)
            severityByGroupID[groupID] = groupHosts.map { severityByHostID[$0.hostid] ?? 0 }.max() ?? 0
        }

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
            let severity = Self.mapElementSeverity(
                elementType: selement.elementtype.intValue,
                references: selement.elements,
                severityByHostID: severityByHostID,
                severityByTriggerID: severityByTriggerID,
                severityByGroupID: severityByGroupID
            )
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
    /// Renders the widget's authored `navtree` hierarchy — previously the resolver took no widget and
    /// listed every map on the server instead. The tree is stored as a flat set of `navtree.N.*`
    /// nodes (name / parent / order / sysmapid), which are assembled into a depth-tagged ordered list.
    private func resolveMapNavigationTree(
        _ widget: ZabbixWidget,
        serverBaseURL: URL,
        authToken: String
    ) async throws -> DashboardWidgetKind {
        let nodes = Self.buildNavTree(from: widget.fields)

        // Color each map-linked node by its map's worst active-problem severity (rolled up to parent
        // folders). Fetch every linked map's host elements in one call, then reuse the shared
        // per-host severity lookup.
        let sysmapIDs = Array(Set(nodes.compactMap(\.sysmapid)))
        guard !sysmapIDs.isEmpty else {
            return .navigationTree(nodes)
        }

        let mapElements = try await zabbixAPIClient.mapHostElements(serverBaseURL: serverBaseURL, authToken: authToken, sysmapIDs: sysmapIDs)
        let severityByHostID = try await maxSeverityByHostID(serverBaseURL: serverBaseURL, authToken: authToken)

        var severityBySysmapID: [String: Int] = [:]
        for map in mapElements {
            let hostIDs = map.selements.compactMap { $0.elementtype.intValue == 0 ? $0.elements.first?.hostid : nil }
            severityBySysmapID[map.sysmapid] = hostIDs.map { severityByHostID[$0] ?? 0 }.max() ?? 0
        }

        return .navigationTree(Self.applyNavTreeSeverities(nodes, severityBySysmapID: severityBySysmapID))
    }

    /// Assembles the flat `navtree.N.*` node fields into a pre-order, depth-tagged list: root nodes
    /// (parent 0) first, each followed by its children ordered by `order` then index. Cyclic parent
    /// references are broken by a visited set, and any orphan whose parent doesn't exist is emitted
    /// at the top level so no authored node is silently dropped.
    static func buildNavTree(from fields: [ZabbixWidgetField]) -> [NavTreeNode] {
        var byIndex: [Int: [String: String]] = [:]
        let prefix = "navtree."
        for field in fields where field.name.hasPrefix(prefix) {
            let remainder = field.name.dropFirst(prefix.count)
            let parts = remainder.split(separator: ".", maxSplits: 1)
            guard parts.count == 2, let index = Int(parts[0]) else { continue }
            byIndex[index, default: [:]][String(parts[1])] = field.value
        }
        guard !byIndex.isEmpty else { return [] }

        var childrenByParent: [Int: [Int]] = [:]
        for (index, group) in byIndex {
            childrenByParent[group["parent"].flatMap(Int.init) ?? 0, default: []].append(index)
        }
        func sortedChildren(of parent: Int) -> [Int] {
            (childrenByParent[parent] ?? []).sorted { lhs, rhs in
                let lo = byIndex[lhs]?["order"].flatMap(Int.init) ?? 0
                let ro = byIndex[rhs]?["order"].flatMap(Int.init) ?? 0
                return lo != ro ? lo < ro : lhs < rhs
            }
        }

        var result: [NavTreeNode] = []
        var visited = Set<Int>()
        func visit(_ index: Int, depth: Int) {
            guard let group = byIndex[index], visited.insert(index).inserted else { return }
            let rawSysmapID = group["sysmapid"] ?? "0"
            let sysmapID: String? = (rawSysmapID == "0" || rawSysmapID.isEmpty) ? nil : rawSysmapID
            result.append(NavTreeNode(
                id: String(index),
                name: group["name"] ?? "",
                depth: depth,
                linksToMap: sysmapID != nil,
                sysmapid: sysmapID,
                severity: 0
            ))
            for child in sortedChildren(of: index) { visit(child, depth: depth + 1) }
        }

        for root in sortedChildren(of: 0) { visit(root, depth: 0) }
        // Any node not reached from a parent-0 root (orphan / broken parent ref) renders at top level.
        for index in byIndex.keys.sorted() where !visited.contains(index) { visit(index, depth: 0) }
        return result
    }

    /// Assigns each map-linked node its map's worst severity (`severityBySysmapID`), then rolls that
    /// up so a folder node reflects the worst severity among its descendants. The pre-order list is
    /// walked so each node's descendants are the contiguous following rows with greater depth.
    static func applyNavTreeSeverities(_ nodes: [NavTreeNode], severityBySysmapID: [String: Int]) -> [NavTreeNode] {
        // Leaf severities from each node's own linked map.
        var updated = nodes.map { node in
            NavTreeNode(id: node.id, name: node.name, depth: node.depth, linksToMap: node.linksToMap, sysmapid: node.sysmapid, severity: node.sysmapid.flatMap { severityBySysmapID[$0] } ?? 0)
        }

        // Roll up: a node inherits the worst severity of its descendants (read before mutation, so
        // ancestor rows — earlier in pre-order — see each descendant's leaf value).
        for i in updated.indices {
            var worst = updated[i].severity
            var j = i + 1
            while j < updated.count, updated[j].depth > updated[i].depth {
                worst = max(worst, updated[j].severity)
                j += 1
            }
            updated[i] = NavTreeNode(id: updated[i].id, name: updated[i].name, depth: updated[i].depth, linksToMap: updated[i].linksToMap, sysmapid: updated[i].sysmapid, severity: worst)
        }
        return updated
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

        let shownHosts = Array(hosts.prefix(showLines))
        let entries = shownHosts.map { host in
            HostListEntry(
                id: host.hostid,
                name: host.name,
                problemCount: countByHostID[host.hostid] ?? 0,
                maxSeverity: maxSeverityByHostID[host.hostid] ?? 0
            )
        }

        // `group_by` (any level configured) breaks the flat list into sections by host group. A host
        // in several groups appears under each; a host with none goes under "Ungrouped".
        let grouped = !Self.indexedFieldGroups(widget.fields, prefix: "group_by").isEmpty
        var pairs: [(key: String, entry: HostListEntry)] = []
        if grouped {
            let hostGroups = try await zabbixAPIClient.hostGroups(serverBaseURL: serverBaseURL, authToken: authToken, hostIDs: shownHosts.map(\.hostid))
            let groupNamesByHostID = Dictionary(uniqueKeysWithValues: hostGroups.map { ($0.hostid, $0.hostgroups.map(\.name)) })
            for entry in entries {
                let names = groupNamesByHostID[entry.id] ?? []
                if names.isEmpty {
                    pairs.append((key: "Ungrouped", entry: entry))
                } else {
                    for name in names { pairs.append((key: name, entry: entry)) }
                }
            }
        } else {
            pairs = entries.map { (key: "", entry: $0) }
        }

        return .hostList(
            Self.groupedSections(pairs, grouped: grouped).map { section in
                HostListSection(id: section.title.isEmpty ? "all" : section.title, title: section.title, hosts: section.entries)
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

        // `group_by` (any level configured) breaks the flat list into sections by host.
        let grouped = !Self.indexedFieldGroups(widget.fields, prefix: "group_by").isEmpty
        let pairs = items.prefix(showLines).map { item -> (key: String, entry: ItemListEntry) in
            let hostName = item.hosts.first?.name ?? ""
            let entry = ItemListEntry(
                id: item.itemid,
                name: item.name,
                hostName: hostName,
                lastValue: Self.mappedItemValue(rawValue: item.lastvalue, valueMap: item.valuemap?.valueMap),
                units: item.units ?? ""
            )
            return (key: grouped ? (hostName.isEmpty ? "Ungrouped" : hostName) : "", entry: entry)
        }

        return .itemList(
            Self.groupedSections(Array(pairs), grouped: grouped).map { section in
                ItemListSection(id: section.title.isEmpty ? "all" : section.title, title: section.title, items: section.entries)
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
        guard let sla = slas.first else {
            return .slaReport([])
        }

        let targetSLO = Double(sla.slo)
        let serviceIDs = Self.indexedValues(widget.fields, name: "serviceid")

        // Compute the achieved SLI for the latest period via sla.getsli. If it fails or returns
        // nothing (e.g. no services attached), fall back to just the SLA's configured target so the
        // widget still renders rather than going blank.
        let report = try? await zabbixAPIClient.sli(
            serverBaseURL: serverBaseURL,
            authToken: authToken,
            slaID: sla.slaid,
            serviceIDs: serviceIDs.isEmpty ? nil : serviceIDs,
            periods: 1
        )

        guard let report, let latestPeriod = report.sli.first, !report.serviceids.isEmpty else {
            return .slaReport([
                SLAReportEntry(id: sla.slaid, name: sla.name, targetSLO: Self.formatSLOPercent(sla.slo), achievedSLI: nil, meetsTarget: nil)
            ])
        }

        // Label each reported service by name (service.get), falling back to the SLA name.
        let serviceNames = try await zabbixAPIClient.services(serverBaseURL: serverBaseURL, authToken: authToken, serviceIDs: report.serviceids)
        let nameByServiceID = Dictionary(uniqueKeysWithValues: serviceNames.map { ($0.serviceid, $0.name) })

        let entries = report.serviceids.enumerated().map { index, serviceID -> SLAReportEntry in
            let achieved = index < latestPeriod.count ? latestPeriod[index].sli : nil
            return SLAReportEntry(
                id: "\(sla.slaid).\(serviceID)",
                name: nameByServiceID[serviceID] ?? sla.name,
                targetSLO: Self.formatSLOPercent(sla.slo),
                achievedSLI: achieved.map { Self.formatSLIPercent($0) },
                meetsTarget: (achieved != nil && targetSLO != nil) ? achieved! >= targetSLO! : nil
            )
        }

        return .slaReport(entries)
    }

    /// Formats a configured SLO string ("99.9000") as a trimmed percentage ("99.9%").
    static func formatSLOPercent(_ slo: String) -> String {
        guard let value = Double(slo) else { return "\(slo)%" }
        return "\(formatSLIPercent(value))"
    }

    /// Formats an SLI/SLO percentage with up to four decimals, trailing zeros trimmed ("99.95%").
    static func formatSLIPercent(_ value: Double) -> String {
        let rounded = (value * 10000).rounded() / 10000
        if rounded == rounded.rounded() {
            return "\(Int(rounded))%"
        }
        var text = String(format: "%.4f", rounded)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return "\(text)%"
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

        // The widget's content filters — recipients (users), actions, media types, and delivery
        // statuses — narrow which alerts are shown. Each maps to an `alert.get` parameter and is
        // applied only when the widget actually configures it, so an unfiltered widget is unchanged.
        let actionIDs = Self.indexedValues(widget.fields, name: "actionids")
        let mediatypeIDs = Self.indexedValues(widget.fields, name: "mediatypeids")
        let userIDs = Self.indexedValues(widget.fields, name: "userids")
        let statuses = Self.indexedValues(widget.fields, name: "statuses").compactMap(Int.init)

        let alerts = try await zabbixAPIClient.alerts(
            serverBaseURL: serverBaseURL,
            authToken: authToken,
            sinceUnixTime: sinceUnixTime,
            limit: showLines,
            actionIDs: actionIDs.isEmpty ? nil : actionIDs,
            mediatypeIDs: mediatypeIDs.isEmpty ? nil : mediatypeIDs,
            userIDs: userIDs.isEmpty ? nil : userIDs,
            statuses: statuses.isEmpty ? nil : statuses
        )

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

        let allScenarios = try await zabbixAPIClient.webScenarios(
            serverBaseURL: serverBaseURL,
            authToken: authToken,
            groupIDs: groupIDs.isEmpty ? nil : groupIDs,
            hostIDs: hostIDs.isEmpty ? nil : hostIDs,
            tags: Self.tagFilters(from: widget.fields),
            evalType: Self.tagEvalType(from: widget.fields)
        )

        // exclude_groupids drops scenarios whose host is in an excluded group — httptest.get has no
        // exclude param, so resolve the scenario hosts' groups and filter client-side (the same
        // approach the problem widgets use for their exclusion).
        let excludedGroupIDs = Set(Self.indexedValues(widget.fields, name: "exclude_groupids"))
        var scenarios = allScenarios
        if !excludedGroupIDs.isEmpty {
            let scenarioHostIDs = Array(Set(allScenarios.compactMap { $0.hosts.first?.hostid }))
            let hostGroups = try await zabbixAPIClient.hostGroups(serverBaseURL: serverBaseURL, authToken: authToken, hostIDs: scenarioHostIDs)
            let groupIDsByHostID = Dictionary(uniqueKeysWithValues: hostGroups.map { ($0.hostid, Set($0.hostgroups.map(\.groupid))) })
            scenarios = allScenarios.filter { scenario in
                guard let hostID = scenario.hosts.first?.hostid else { return true }
                return groupIDsByHostID[hostID, default: []].isDisjoint(with: excludedGroupIDs)
            }
        }

        // Each scenario's Ok/Failed state lives in its `web.test.fail[<name>]` item; fetch them all
        // in one call and key them by (host, scenario name) so each scenario finds its own status.
        let failItems = try await zabbixAPIClient.webTestFailItems(
            serverBaseURL: serverBaseURL,
            authToken: authToken,
            groupIDs: groupIDs.isEmpty ? nil : groupIDs,
            hostIDs: hostIDs.isEmpty ? nil : hostIDs
        )
        var failValueByHostAndScenario: [String: String?] = [:]
        for item in failItems {
            guard let name = Self.scenarioName(fromFailKey: item.key_) else { continue }
            failValueByHostAndScenario[Self.webStatusKey(hostID: item.hostid, scenarioName: name)] = item.lastvalue
        }

        return .webMonitoring(
            scenarios.map { scenario in
                let hostID = scenario.hosts.first?.hostid
                let failValue = hostID.flatMap { failValueByHostAndScenario[Self.webStatusKey(hostID: $0, scenarioName: scenario.name)] ?? nil }
                return WebScenarioSummary(
                    id: scenario.httptestid,
                    name: scenario.name,
                    hostName: scenario.hosts.first?.name,
                    status: Self.webScenarioStatus(fromFailValue: failValue)
                )
            }
        )
    }

    /// Composite dictionary key pairing a host with a scenario name, so two hosts running a
    /// same-named scenario don't collide.
    static func webStatusKey(hostID: String, scenarioName: String) -> String {
        "\(hostID)\u{1}\(scenarioName)"
    }

    /// Extracts the scenario name from a `web.test.fail[<name>]` item key, or nil if the key isn't
    /// a fail-status item. (Names Zabbix quotes in the key — those containing `]` or `,` — aren't
    /// unwrapped here; the common unquoted case is handled.)
    static func scenarioName(fromFailKey key: String) -> String? {
        let prefix = "web.test.fail["
        guard key.hasPrefix(prefix), key.hasSuffix("]") else { return nil }
        return String(key.dropFirst(prefix.count).dropLast())
    }

    /// Maps a `web.test.fail` reading to a scenario status: 0 = Ok, > 0 = Failed (the failed step),
    /// and a missing/non-numeric value = Unknown (never collected).
    static func webScenarioStatus(fromFailValue value: String?) -> WebScenarioStatus {
        guard let value, let failedStep = Double(value) else { return .unknown }
        return failedStep > 0 ? .failed : .ok
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
        let columnGroups = Self.indexedFieldGroups(widget.fields, prefix: "columns")
        let itemIDs = columnGroups.compactMap { $0["itemid"] }.filter { !$0.isEmpty }
        guard !itemIDs.isEmpty else {
            return .unsupported(rawType: widget.type)
        }
        // A column's own display name ("Memory") overrides the item's name, per column config.
        let columnNameByItemID = Dictionary(uniqueKeysWithValues: columnGroups.compactMap { group -> (String, String)? in
            guard let itemID = group["itemid"], let name = group["name"], !name.isEmpty else { return nil }
            return (itemID, name)
        })

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

            // Format each reading with Zabbix's default convert_units precision — a value map wins,
            // an unmapped numeric reading is scaled, unit-suffixed, and trimmed ("4.58 GB", "4 GB",
            // not "4.00 GB"), and text/log readings pass through — matching the frontend's own
            // history rows, which have no decimal-places setting.
            let units = item.units ?? ""
            series.append(
                ItemHistorySeries(
                    id: item.itemid,
                    itemName: columnNameByItemID[item.itemid] ?? item.name,
                    values: windowed.map { value in
                        ItemHistoryPoint(
                            id: "\(item.itemid).\(value.clock)",
                            value: Self.formattedDefaultValue(rawValue: value.value, units: units, valueMap: item.valuemap?.valueMap),
                            date: Date(timeIntervalSince1970: TimeInterval(value.clock) ?? 0)
                        )
                    }
                )
            )
        }

        // Zabbix's widget hides timestamps unless "show_timestamp" is enabled (verified live: the
        // default config carries show_timestamp 0 and renders name/value rows only).
        return .itemHistory(series, showTimestamp: Self.fieldValue(widget.fields, name: "show_timestamp") == "1")
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

        // "style": 0 = hosts as rows / items as columns (default), 1 = transposed.
        let transpose = Self.fieldValue(widget.fields, name: "style").flatMap(Int.init) == 1

        // The Data overview widget has no decimal-places setting: every cell uses Zabbix's default
        // convert_units precision ("90.7659 %", "0.002083 %", "4 GB"), not a fixed two decimals.
        let entries = items.prefix(100).map { item in
            (host: item.hosts.first?.name ?? "",
             item: item.name,
             value: Self.formattedDefaultValue(rawValue: item.lastvalue, units: item.units ?? "", valueMap: item.valuemap?.valueMap))
        }

        return .dataOverview(Self.buildDataOverviewMatrix(Array(entries), transpose: transpose))
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
            let approximation = dataset["approximation"].flatMap(Int.init) ?? 2
            let timeshift = dataset["timeshift"].flatMap(Self.durationSeconds) ?? 0
            let aggregateFunction = dataset["aggregate_function"].flatMap(Int.init) ?? 0
            let aggregateInterval = dataset["aggregate_interval"].flatMap(Self.durationSeconds) ?? 0

            var matchedSeries: [(id: String, name: String, units: String, points: [ChartPoint])] = []
            for host in hosts {
                for itemPattern in itemPatterns {
                    let items = try await zabbixAPIClient.itemsMatching(
                        serverBaseURL: serverBaseURL,
                        authToken: authToken,
                        hostIDs: [host.hostid],
                        namePattern: itemPattern
                    )

                    for item in items {
                        let points = try await recentPoints(for: item.itemid, valueType: item.value_type?.intValue ?? 0, windowStart: windowStart, windowEnd: windowEnd, approximation: approximation, timeshiftSeconds: timeshift, aggregateFunction: aggregateFunction, aggregateIntervalSeconds: aggregateInterval, serverBaseURL: serverBaseURL, authToken: authToken)

                        matchedSeries.append((id: "\(widget.widgetid).\(item.itemid)", name: "\(host.name): \(item.name)", units: item.units ?? "", points: points))
                    }
                }
            }

            // Zabbix sorts a pattern's matches by name and colors each with a variation of the
            // dataset's one base color (dark to light) — which needs the total match count, so
            // colors are assigned after the whole dataset resolves.
            matchedSeries.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            for (index, matched) in matchedSeries.enumerated() {
                series.append(
                    ChartSeries(
                        id: matched.id,
                        name: matched.name,
                        colorHex: Self.variationColorHex(baseColorHex, index: index, count: matchedSeries.count),
                        units: matched.units,
                        fillOpacity: fillOpacity,
                        points: matched.points
                    )
                )
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

            let approximation = override["approximation"].flatMap(Int.init) ?? 2
            let timeshift = override["timeshift"].flatMap(Self.durationSeconds) ?? 0
            let aggregateFunction = override["aggregate_function"].flatMap(Int.init) ?? 0
            let aggregateInterval = override["aggregate_interval"].flatMap(Self.durationSeconds) ?? 0
            let points = try await recentPoints(for: item.itemid, valueType: item.value_type?.intValue ?? 0, windowStart: windowStart, windowEnd: windowEnd, approximation: approximation, timeshiftSeconds: timeshift, aggregateFunction: aggregateFunction, aggregateIntervalSeconds: aggregateInterval, serverBaseURL: serverBaseURL, authToken: authToken)

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
        return series.isEmpty ? .unsupported(rawType: widget.type) : .lineChart(series: series, window: window, stacked: false, showLegend: Self.fieldValue(widget.fields, name: "legend") != "0", showLegendStats: false, yMin: Self.fieldValue(widget.fields, name: "lefty_min").flatMap(Double.init), yMax: Self.fieldValue(widget.fields, name: "lefty_max").flatMap(Double.init), triggerLines: [], axisStyle: .svg)
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

    /// Zabbix's own per-item color variation for a multi-item dataset: each matched item's color
    /// is the dataset's base color with every RGB channel shifted by an even step from −64 to +64
    /// across the items (clamped per channel), producing the dark-to-light run the frontend shows
    /// — verified against the live pie chart's legend, where base FF465C renders maroon for the
    /// first item through light pink for the last.
    static func variationColorHex(_ hex: String, index: Int, count: Int) -> String {
        guard count > 1, hex.count == 6, let value = UInt32(hex, radix: 16) else { return hex }

        let shift = Int((Double(index) * 128.0 / Double(count - 1)).rounded()) - 64
        func shifted(_ component: UInt32) -> Int {
            max(0, min(255, Int(component) + shift))
        }

        return String(format: "%02X%02X%02X", shifted((value >> 16) & 0xFF), shifted((value >> 8) & 0xFF), shifted(value & 0xFF))
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

    /// The graph reference is stored under the indexed field name `graphid.0` (verified against a live
    /// classic "graph" widget), so it must be read with `firstIndexedValue` — an exact-name lookup for
    /// "graphid" misses it and the widget falls through to `.unsupported`.
    private func resolveClassicGraph(
        _ widget: ZabbixWidget,
        serverBaseURL: URL,
        authToken: String
    ) async throws -> DashboardWidgetKind {
        let (windowStart, windowEnd) = Self.timePeriod(from: widget.fields)

        // Simple-graph mode: the widget references a single `itemid` directly (no configured graph),
        // plotted as its own line — previously returned .unsupported.
        if Self.firstIndexedValue(widget.fields, name: "graphid") == nil,
           let itemID = Self.firstIndexedValue(widget.fields, name: "itemid") {
            let items = try await zabbixAPIClient.items(serverBaseURL: serverBaseURL, authToken: authToken, itemIDs: [itemID])
            // The configured item resolved to nothing — deleted, or not visible to this account.
            guard let item = items.first else { return .referencedObjectUnavailable }
            let points = try await recentPoints(for: item.itemid, valueType: item.value_type?.intValue ?? 0, windowStart: windowStart, windowEnd: windowEnd, serverBaseURL: serverBaseURL, authToken: authToken)
            let series = [ChartSeries(id: "\(widget.widgetid).\(item.itemid)", name: item.name, colorHex: "3DC9B0", units: item.units ?? "", fillOpacity: 0.5, points: points)]
            // Zabbix's default Simple-graph header is "HOST: item name".
            pendingDefaultTitle = Self.hostPrefixedTitle(host: item.hosts?.first?.name, name: item.name)
            let simpleTriggerLines = await triggerLines(forItemIDs: [item.itemid], serverBaseURL: serverBaseURL, authToken: authToken)
            return .lineChart(series: series, window: ChartTimeWindow(start: windowStart, end: windowEnd), stacked: false, showLegend: Self.fieldValue(widget.fields, name: "legend") != "0", showLegendStats: true, yMin: nil, yMax: nil, triggerLines: simpleTriggerLines, axisStyle: .classic)
        }

        guard let graphID = Self.firstIndexedValue(widget.fields, name: "graphid") else {
            return .unsupported(rawType: widget.type)
        }

        let graphs = try await zabbixAPIClient.graphs(serverBaseURL: serverBaseURL, authToken: authToken, graphIDs: [graphID])
        guard let graph = graphs.first else {
            // The configured graph resolved to nothing — deleted, or not visible to this account.
            return .referencedObjectUnavailable
        }
        guard !graph.gitems.isEmpty else {
            return .unsupported(rawType: widget.type)
        }

        let items = try await zabbixAPIClient.items(serverBaseURL: serverBaseURL, authToken: authToken, itemIDs: graph.gitems.map(\.itemid))
        let itemsByID = Dictionary(uniqueKeysWithValues: items.map { ($0.itemid, $0) })

        // Pie / exploded-pie graphs (graphtype 2/3) are a fundamentally different shape — render them
        // as a pie of each item's latest value rather than misdrawing them as overlaid lines. Normal
        // (0) and stacked (1) both render as a line chart; true visual stacking for type 1 is a
        // follow-up (the data is correct either way, only the cumulative baseline differs).
        let graphType = graph.graphtype?.intValue ?? 0
        if graphType == 2 || graphType == 3 {
            let slices = graph.gitems.compactMap { gitem -> ChartSlice? in
                guard let item = itemsByID[gitem.itemid], let value = item.lastvalue.flatMap(Double.init) else { return nil }
                return ChartSlice(id: "\(widget.widgetid).\(item.itemid)", name: item.name, colorHex: gitem.color, value: value)
            }
            // Zabbix's default classic-graph header is "HOST: graph name".
            pendingDefaultTitle = Self.hostPrefixedTitle(host: graph.gitems.first.flatMap { itemsByID[$0.itemid]?.hosts?.first?.name }, name: graph.name)
            return slices.isEmpty ? .unsupported(rawType: widget.type) : .pieChart(slices, isDonut: false, legendShowsValue: true)
        }

        var series: [ChartSeries] = []
        for gitem in graph.gitems {
            guard let item = itemsByID[gitem.itemid] else { continue }

            let points = try await recentPoints(for: item.itemid, valueType: item.value_type?.intValue ?? 0, windowStart: windowStart, windowEnd: windowEnd, serverBaseURL: serverBaseURL, authToken: authToken)

            series.append(ChartSeries(id: "\(widget.widgetid).\(item.itemid)", name: item.name, colorHex: gitem.color, units: item.units ?? "", fillOpacity: 0.5, points: points))
        }

        let window = ChartTimeWindow(start: windowStart, end: windowEnd)
        // The graph object's own fixed Y-axis bounds (ymin_type/ymax_type == 1) pin the chart's
        // scale the way Zabbix draws it — e.g. a CPU graph fixed 0–100 renders the full band even
        // when the data hugs zero. Calculated (0) and item-tied (2) modes leave the bound to the
        // data. (The old code read svggraph's lefty_min/lefty_max here, fields a classic graph
        // widget never carries.)
        let yMin = graph.ymin_type?.intValue == 1 ? graph.yaxismin.flatMap(Double.init) : nil
        let yMax = graph.ymax_type?.intValue == 1 ? graph.yaxismax.flatMap(Double.init) : nil
        // Classic graph type 1 is a stacked graph; 0 is a normal overlaid line chart. Classic graphs
        // render Zabbix's stats legend (last/min/avg/max per series).
        // Zabbix's default classic-graph header is "HOST: graph name".
        pendingDefaultTitle = Self.hostPrefixedTitle(host: graph.gitems.first.flatMap { itemsByID[$0.itemid]?.hosts?.first?.name }, name: graph.name)
        let graphTriggerLines = await triggerLines(forItemIDs: graph.gitems.map(\.itemid), serverBaseURL: serverBaseURL, authToken: authToken)
        return series.isEmpty ? .unsupported(rawType: widget.type) : .lineChart(series: series, window: window, stacked: graphType == 1, showLegend: Self.fieldValue(widget.fields, name: "legend") != "0", showLegendStats: true, yMin: yMin, yMax: yMax, triggerLines: graphTriggerLines, axisStyle: .classic)
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
        let decimalPlaces = Self.fieldValue(widget.fields, name: "decimal_places").flatMap(Int.init) ?? 2
        var slices: [ChartSlice] = []

        for (datasetIndex, dataset) in datasets.enumerated() {
            let hostNames = Self.valuesWithNumberedSuffix(dataset, prefix: "hosts.")
            let itemPatterns = Self.valuesWithNumberedSuffix(dataset, prefix: "items.")
            guard !hostNames.isEmpty, !itemPatterns.isEmpty else { continue }

            let baseColorHex = dataset["color"] ?? "3DC9B0"
            let aggregateFunction = dataset["aggregate_function"].flatMap(Int.init) ?? 0
            let datasetAggregation = dataset["dataset_aggregation"].flatMap(Int.init) ?? 0

            let hosts = try await zabbixAPIClient.hostsByName(serverBaseURL: serverBaseURL, authToken: authToken, names: hostNames)

            // One (id, label, units, value) per matched item across every host/pattern in the dataset.
            var matched: [(id: String, label: String, units: String, value: Double)] = []
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
                        matched.append((id: item.itemid, label: "\(host.name): \(item.name)", units: item.units ?? "", value: value))
                    }
                }
            }
            guard !matched.isEmpty else { continue }

            if datasetAggregation > 0 {
                // Collapse every matched item into one combined slice for this dataset.
                guard let combined = Self.aggregate(matched.map { (clock: 0, value: $0.value) }, function: datasetAggregation) else { continue }
                let units = matched.first?.units ?? ""
                slices.append(ChartSlice(id: "\(widget.widgetid).ds\(datasetIndex)", name: matched.first?.label ?? "Data set \(datasetIndex + 1)", colorHex: baseColorHex, value: combined, valueLabel: ZabbixValueFormatting.formatItemValue(combined, units: units, decimalPlaces: decimalPlaces)))
            } else {
                // One slice per matched item, sorted by name and colored with Zabbix's dark-to-
                // light variations of the dataset's base color — matching the frontend's legend
                // order and chip colors exactly.
                matched.sort { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
                for (index, entry) in matched.enumerated() {
                    slices.append(ChartSlice(id: "\(widget.widgetid).\(entry.id)", name: entry.label, colorHex: Self.variationColorHex(baseColorHex, index: index, count: matched.count), value: entry.value, valueLabel: ZabbixValueFormatting.formatItemValue(entry.value, units: entry.units, decimalPlaces: decimalPlaces)))
                }
            }
        }

        // Zabbix's pie chart is a full pie by default; `draw_type` 1 switches to a doughnut.
        return slices.isEmpty ? .unsupported(rawType: widget.type) : .pieChart(slices, isDonut: Self.fieldValue(widget.fields, name: "draw_type") == "1", legendShowsValue: Self.fieldValue(widget.fields, name: "legend_value") == "1")
    }

    // MARK: - System information

    /// Builds Zabbix's System information table: server-running status, the frontend/API version,
    /// and host/template/item/trigger tallies via `countOutput` queries, plus the server's required
    /// performance reading. Every count is computed server-side and scoped to the authenticated
    /// account's visibility — a limited account sees its own (smaller) numbers, exactly as Zabbix's
    /// frontend scopes what it shows that account — and each count is best-effort, so a row the
    /// account can't compute is omitted rather than failing the widget.
    private func resolveSystemInformation(
        _ widget: ZabbixWidget,
        serverBaseURL: URL,
        authToken: String
    ) async throws -> DashboardWidgetKind {
        // "info_type": 0 = server stats, 1 = high-availability nodes. hanode.get (6.0+) both
        // populates the HA-nodes list and gives a real running signal (some node active). It's
        // best-effort: a standalone server returns no nodes, and older servers error — either
        // way we fall back to the API-success proxy below.
        let infoType = Self.fieldValue(widget.fields, name: "info_type").flatMap(Int.init) ?? 0
        let nodes = (try? await zabbixAPIClient.haNodes(serverBaseURL: serverBaseURL, authToken: authToken)) ?? []

        if infoType == 1 {
            let haNodes = nodes.enumerated().map { index, node -> SystemHANode in
                SystemHANode(
                    id: node.name.isEmpty ? "node-\(index)" : node.name,
                    name: node.name.isEmpty ? "Standalone" : node.name,
                    statusLabel: Self.haNodeStatusLabel(node.status.intValue),
                    isActive: node.status.intValue == 3
                )
            }
            return .systemInformation(rows: [], haNodes: haNodes)
        }

        // Zabbix's frontend checks "server is running" via a direct socket to the trapper port,
        // unreachable here. When HA nodes are known, an active node means the server is up;
        // otherwise a live authenticated session is the closest available proxy.
        let isRunning = Self.isServerRunning(fromHANodeStatuses: nodes.map { $0.status.intValue }) ?? true

        let frontendVersion = try await zabbixAPIClient.apiVersion(serverBaseURL: serverBaseURL)

        // The tallies, concurrently. Filters mirror Zabbix's own System information report:
        // items split enabled (status 0, state 0) / disabled (status 1) / not supported (status 0,
        // state 1); triggers split enabled/disabled with the enabled ones sub-split problem/ok.
        async let hostsEnabled = try? zabbixAPIClient.objectCount(method: "host.get", filter: ["status": "0"], serverBaseURL: serverBaseURL, authToken: authToken)
        async let hostsDisabled = try? zabbixAPIClient.objectCount(method: "host.get", filter: ["status": "1"], serverBaseURL: serverBaseURL, authToken: authToken)
        async let templates = try? zabbixAPIClient.objectCount(method: "template.get", filter: nil, serverBaseURL: serverBaseURL, authToken: authToken)
        async let itemsEnabled = try? zabbixAPIClient.objectCount(method: "item.get", filter: ["status": "0", "state": "0"], serverBaseURL: serverBaseURL, authToken: authToken)
        async let itemsDisabled = try? zabbixAPIClient.objectCount(method: "item.get", filter: ["status": "1"], serverBaseURL: serverBaseURL, authToken: authToken)
        async let itemsNotSupported = try? zabbixAPIClient.objectCount(method: "item.get", filter: ["status": "0", "state": "1"], serverBaseURL: serverBaseURL, authToken: authToken)
        async let triggersEnabled = try? zabbixAPIClient.objectCount(method: "trigger.get", filter: ["status": "0"], serverBaseURL: serverBaseURL, authToken: authToken)
        async let triggersDisabled = try? zabbixAPIClient.objectCount(method: "trigger.get", filter: ["status": "1"], serverBaseURL: serverBaseURL, authToken: authToken)
        async let triggersProblem = try? zabbixAPIClient.objectCount(method: "trigger.get", filter: ["status": "0", "value": "1"], serverBaseURL: serverBaseURL, authToken: authToken)
        async let triggersOK = try? zabbixAPIClient.objectCount(method: "trigger.get", filter: ["status": "0", "value": "0"], serverBaseURL: serverBaseURL, authToken: authToken)
        async let requiredPerformance = try? zabbixAPIClient.itemByKey(serverBaseURL: serverBaseURL, authToken: authToken, key: "zabbix[requiredperformance]")

        var rows: [SystemInfoRow] = [
            SystemInfoRow(id: "running", parameter: "Zabbix server is running", value: isRunning ? "Yes" : "No", valueTint: isRunning ? .green : .red)
        ]

        // apiinfo.version reports the frontend/API version (what Zabbix's own table labels
        // "Zabbix frontend version"); the server binary's version isn't exposed via the JSON-RPC
        // API, so that row is omitted rather than mislabeled.
        rows.append(SystemInfoRow(id: "frontend", parameter: "Zabbix frontend version", value: frontendVersion))

        if let enabled = await hostsEnabled, let disabled = await hostsDisabled {
            rows.append(SystemInfoRow(id: "hosts", parameter: "Number of hosts (enabled/disabled)", value: "\(enabled + disabled)", details: [
                SystemInfoDetailSegment(id: "e", text: "\(enabled)", tint: .green),
                SystemInfoDetailSegment(id: "s1", text: " / "),
                SystemInfoDetailSegment(id: "d", text: "\(disabled)", tint: .red)
            ]))
        }

        if let templates = await templates {
            rows.append(SystemInfoRow(id: "templates", parameter: "Number of templates", value: "\(templates)"))
        }

        if let enabled = await itemsEnabled, let disabled = await itemsDisabled, let notSupported = await itemsNotSupported {
            rows.append(SystemInfoRow(id: "items", parameter: "Number of items (enabled/disabled/not supported)", value: "\(enabled + disabled + notSupported)", details: [
                SystemInfoDetailSegment(id: "e", text: "\(enabled)", tint: .green),
                SystemInfoDetailSegment(id: "s1", text: " / "),
                SystemInfoDetailSegment(id: "d", text: "\(disabled)", tint: .red),
                SystemInfoDetailSegment(id: "s2", text: " / "),
                SystemInfoDetailSegment(id: "n", text: "\(notSupported)", tint: .gray)
            ]))
        }

        if let enabled = await triggersEnabled, let disabled = await triggersDisabled, let problem = await triggersProblem, let ok = await triggersOK {
            rows.append(SystemInfoRow(id: "triggers", parameter: "Number of triggers (enabled/disabled [problem/ok])", value: "\(enabled + disabled)", details: [
                SystemInfoDetailSegment(id: "e", text: "\(enabled)", tint: .green),
                SystemInfoDetailSegment(id: "s1", text: " / "),
                SystemInfoDetailSegment(id: "d", text: "\(disabled)", tint: .red),
                SystemInfoDetailSegment(id: "s2", text: " ["),
                SystemInfoDetailSegment(id: "p", text: "\(problem)", tint: .red),
                SystemInfoDetailSegment(id: "s3", text: " / "),
                SystemInfoDetailSegment(id: "o", text: "\(ok)", tint: .green),
                SystemInfoDetailSegment(id: "s4", text: "]")
            ]))
        }

        if let nvps = await requiredPerformance?.lastvalue.flatMap(Double.init) {
            rows.append(SystemInfoRow(id: "nvps", parameter: "Required server performance, new values per second", value: String(format: "%.2f", nvps)))
        }

        return .systemInformation(rows: rows, haNodes: [])
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

    /// Picks the trend field a dataset's `approximation` calls for: 1 = min, 3 = max, everything else
    /// (2 = avg, 0 = all, or absent) = avg — since a single rendered line can't draw the min/avg/max
    /// band that "all" means, it falls back to the average Zabbix draws by default.
    static func trendValue(from value: ZabbixTrendValue, approximation: Int) -> String? {
        switch approximation {
        case 1: return value.value_min ?? value.value_avg
        case 3: return value.value_max ?? value.value_avg
        default: return value.value_avg
        }
    }

    private func recentPoints(
        for itemID: String,
        valueType: Int,
        windowStart: Date,
        windowEnd: Date,
        approximation: Int = 2,
        timeshiftSeconds: TimeInterval = 0,
        aggregateFunction: Int = 0,
        aggregateIntervalSeconds: TimeInterval = 0,
        serverBaseURL: URL,
        authToken: String
    ) async throws -> [ChartPoint] {
        // Timeshift moves the data source window (e.g. "1w" to overlay last week on this week); fetch
        // the shifted window, then shift each sample forward by the same amount so it aligns on the
        // current axis for comparison.
        let fetchStart = windowStart.addingTimeInterval(-timeshiftSeconds)
        let fetchEnd = windowEnd.addingTimeInterval(-timeshiftSeconds)

        let values = try await zabbixAPIClient.history(
            serverBaseURL: serverBaseURL,
            authToken: authToken,
            itemID: itemID,
            historyValueType: valueType,
            sinceUnixTime: Int(fetchStart.timeIntervalSince1970),
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
        let earliestHistory = points.first?.date ?? fetchEnd
        if earliestHistory.timeIntervalSince(fetchStart) > Self.trendFillMinimumGapSeconds {
            let trendValues = try await zabbixAPIClient.trends(
                serverBaseURL: serverBaseURL,
                authToken: authToken,
                itemID: itemID,
                sinceUnixTime: Int(fetchStart.timeIntervalSince1970),
                untilUnixTime: Int(earliestHistory.timeIntervalSince1970)
            )
            let trendPoints = trendValues.compactMap { value -> (date: Date, value: Double)? in
                guard let selected = Self.trendValue(from: value, approximation: approximation).flatMap(Double.init),
                      let timestamp = TimeInterval(value.clock) else {
                    return nil
                }
                return (Date(timeIntervalSince1970: timestamp), selected)
            }.filter { $0.date < earliestHistory }

            points = (trendPoints + points).sorted { $0.date < $1.date }
        }

        // Re-align the shifted samples onto the current axis before bucketing.
        if timeshiftSeconds != 0 {
            points = points.map { (date: $0.date.addingTimeInterval(timeshiftSeconds), value: $0.value) }
        }

        // Aggregate into interval buckets when the dataset configures it (min/max/avg/…), rather
        // than plotting every raw sample.
        points = Self.aggregatedByInterval(points, function: aggregateFunction, intervalSeconds: aggregateIntervalSeconds, windowStart: windowStart)

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

    /// Parses a Zabbix duration field (svggraph `timeshift` / `aggregate_interval`) into seconds:
    /// a plain integer is seconds, or a magnitude with an `s`/`m`/`h`/`d`/`w` suffix (here `m` is
    /// minutes). An optional leading `-`/`+` sets the sign. Returns nil for an empty/unparseable
    /// value so the caller treats it as "no shift / no aggregation".
    static func durationSeconds(from raw: String) -> TimeInterval? {
        var text = raw.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }

        var sign = 1.0
        if text.hasPrefix("-") { sign = -1; text.removeFirst() }
        else if text.hasPrefix("+") { text.removeFirst() }

        if let plainSeconds = Double(text) { return sign * plainSeconds }

        guard let unit = text.last, let magnitude = Double(text.dropLast()) else { return nil }
        let multiplier: Double
        switch unit {
        case "s": multiplier = 1
        case "m": multiplier = 60
        case "h": multiplier = 3600
        case "d": multiplier = 86400
        case "w": multiplier = 604800
        default: return nil
        }
        return sign * magnitude * multiplier
    }

    /// Aggregates chronological samples into fixed-width interval buckets (svggraph's per-dataset
    /// `aggregate_function` over `aggregate_interval`), applying the function (1 min … 7 last) to each
    /// bucket and placing the result at the bucket's midpoint. Returns the points unchanged when no
    /// function is set or the interval is non-positive.
    static func aggregatedByInterval(
        _ points: [(date: Date, value: Double)],
        function: Int,
        intervalSeconds: TimeInterval,
        windowStart: Date
    ) -> [(date: Date, value: Double)] {
        guard function > 0, intervalSeconds > 0, !points.isEmpty else { return points }

        let origin = windowStart.timeIntervalSince1970
        var buckets: [Int: [(clock: Double, value: Double)]] = [:]
        for point in points {
            let clock = point.date.timeIntervalSince1970
            let index = Int((clock - origin) / intervalSeconds)
            buckets[index, default: []].append((clock, point.value))
        }

        return buckets.keys.sorted().compactMap { index in
            guard let value = aggregate(buckets[index] ?? [], function: function) else { return nil }
            let midpoint = origin + (Double(index) + 0.5) * intervalSeconds
            return (Date(timeIntervalSince1970: midpoint), value)
        }
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
    private func maxSeverityByHostID(
        serverBaseURL: URL,
        authToken: String,
        severities: [Int]? = nil,
        tags: [ZabbixTagFilter]? = nil,
        evalType: Int? = nil
    ) async throws -> [String: Int] {
        let resolved = try await activeProblemsWithHostID(
            serverBaseURL: serverBaseURL,
            authToken: authToken,
            severities: severities,
            tags: tags,
            evalType: evalType
        )
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

    /// Row labels matching Zabbix's own host-availability widget. Interface type 1 is the passive
    /// Zabbix agent — Zabbix labels it "Agent (passive)" (its "Agent (active)" row tracks active
    /// checks, which aren't interface-based; surfacing that row needs the hosts' active_available
    /// field, still an audit gap).
    private static func interfaceTypeName(_ type: Int) -> String {
        switch type {
        case 1: "Agent (passive)"
        case 2: "SNMP"
        case 3: "IPMI"
        case 4: "JMX"
        default: "Interface Type \(type)"
        }
    }

    /// Builds a classic graph's trigger threshold lines: every enabled trigger on the graph's items
    /// whose (macro-expanded) expression is a single comparison against a constant, drawn at that
    /// constant in the trigger's severity color — the same set Zabbix's own graphs draw. Complex
    /// expressions are skipped, as Zabbix skips them. Best-effort: a fetch failure just means no
    /// lines rather than failing the graph.
    private func triggerLines(forItemIDs itemIDs: [String], serverBaseURL: URL, authToken: String) async -> [GraphTriggerLine] {
        let triggers = (try? await zabbixAPIClient.triggersForItems(serverBaseURL: serverBaseURL, authToken: authToken, itemIDs: itemIDs)) ?? []
        var lines: [GraphTriggerLine] = []
        for trigger in triggers {
            guard let threshold = Self.simpleTriggerThreshold(fromExpression: trigger.expression) else { continue }
            let colorHex = await SeverityPalette.colorHex(for: trigger.priority.intValue)
            lines.append(GraphTriggerLine(
                id: trigger.triggerid,
                label: "Trigger: \(trigger.description) [\(threshold.comparison) \(threshold.value.formatted(.number.grouping(.never)))]",
                value: threshold.value,
                colorHex: colorHex
            ))
        }
        return lines
    }

    /// Extracts the constant threshold from a simple trigger expression — "last(/host/key)>90",
    /// "avg(/h/k,5m)>=1.5" — the same single-comparison case Zabbix's own classic graphs draw a
    /// trigger line for. Returns nil for compound or non-constant expressions (multiple
    /// comparisons, suffixed constants like "16G", macro thresholds that didn't expand).
    static func simpleTriggerThreshold(fromExpression expression: String?) -> (comparison: String, value: Double)? {
        guard let expression, !expression.isEmpty else { return nil }
        // `[^<>=]+` up front guarantees exactly one comparison in the whole expression; the
        // constant must close the expression.
        let pattern = "^[^<>=]+([<>]=?|=)\\s*(-?[0-9]+(?:\\.[0-9]+)?)\\s*$"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: expression, range: NSRange(expression.startIndex..., in: expression)),
              let comparisonRange = Range(match.range(at: 1), in: expression),
              let valueRange = Range(match.range(at: 2), in: expression),
              let value = Double(expression[valueRange]) else {
            return nil
        }
        return (String(expression[comparisonRange]), value)
    }

    /// Zabbix's data-driven default header for object-referencing widgets: "HOST: name", or just
    /// the name when the host is unknown.
    static func hostPrefixedTitle(host: String?, name: String) -> String {
        guard let host, !host.isEmpty else { return name }
        return "\(host): \(name)"
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

    /// Expands a label template's `{MACRO}` tokens (item value / gauge `description`, honeycomb
    /// labels) from the given values, e.g. "{HOST.NAME}: {ITEM.NAME}". The single-item numbered
    /// variant `{MACRO1}` resolves to the same value. Unrecognized macros are left untouched rather
    /// than blanked, so an unsupported token stays visible rather than silently vanishing.
    static func expandMacros(_ template: String, _ macros: [String: String]) -> String {
        var result = template
        for (key, value) in macros {
            result = result.replacingOccurrences(of: "{\(key)1}", with: value)
            result = result.replacingOccurrences(of: "{\(key)}", with: value)
        }
        return result
    }

    /// Assembles flat (host, item, value) entries into a Data-overview matrix: one row per host,
    /// one column per distinct item name, each in first-seen order, with the value at the crossing
    /// (empty when a host has no such item). `transpose` swaps rows/columns (items as rows) to honor
    /// the widget's orientation.
    static func buildDataOverviewMatrix(_ entries: [(host: String, item: String, value: String)], transpose: Bool) -> DataOverviewMatrix {
        var rowOrder: [String] = []
        var columnOrder: [String] = []
        var rowSeen = Set<String>()
        var columnSeen = Set<String>()
        var valueByRowColumn: [String: [String: String]] = [:]

        for entry in entries {
            let rowKey = transpose ? entry.item : entry.host
            let columnKey = transpose ? entry.host : entry.item
            if rowSeen.insert(rowKey).inserted { rowOrder.append(rowKey) }
            if columnSeen.insert(columnKey).inserted { columnOrder.append(columnKey) }
            valueByRowColumn[rowKey, default: [:]][columnKey] = entry.value
        }

        let rows = rowOrder.map { rowKey in
            DataOverviewMatrixRow(id: rowKey, header: rowKey, cells: columnOrder.map { valueByRowColumn[rowKey]?[$0] ?? "" })
        }
        return DataOverviewMatrix(columnHeaders: columnOrder, rows: rows)
    }

    /// The common item label macros — `{ITEM.NAME}` / `{ITEM.LASTVALUE}` / `{ITEM.VALUE}` /
    /// `{ITEM.UNITS}` / `{HOST.NAME}` — for a single item's label templates. `{ITEM.LASTVALUE}` and
    /// `{ITEM.VALUE}` are value-mapped and unit/precision-formatted like the widget's own value.
    static func itemLabelMacros(itemName: String, hostName: String, lastValue: String?, units: String, valueMap: ZabbixValueMap?, decimalPlaces: Int) -> [String: String] {
        let formatted = formattedItemValue(rawValue: lastValue, units: units, valueMap: valueMap, decimalPlaces: decimalPlaces)
        return [
            "ITEM.NAME": itemName,
            "ITEM.LASTVALUE": formatted,
            "ITEM.VALUE": formatted,
            "ITEM.UNITS": units,
            "HOST.NAME": hostName
        ]
    }

    /// Resolves a single-item widget's label template (item value / gauge `description`) against its
    /// item. Falls back to the item's name when no template is set — Zabbix's own default is
    /// "{ITEM.NAME}", so this reproduces the prior behavior.
    static func expandLabel(template: String?, item: ZabbixItemSummary, decimalPlaces: Int) -> String {
        guard let template, !template.isEmpty else { return item.name }
        return expandMacros(template, itemLabelMacros(
            itemName: item.name,
            hostName: item.hosts?.first?.name ?? "",
            lastValue: item.lastvalue,
            units: item.units ?? "",
            valueMap: item.valuemap?.valueMap,
            decimalPlaces: decimalPlaces
        ))
    }

    /// Like `mappedItemValue`, but an unmapped *numeric* reading is formatted with its units and the
    /// widget's decimal precision (via `formatItemValue`) — "50.00 %", "1.5 Mbps" — rather than shown
    /// as a raw string. Value-mapped ("Up (1)") and non-numeric (text/log) readings are unchanged.
    static func formattedItemValue(rawValue: String?, units: String, valueMap: ZabbixValueMap?, decimalPlaces: Int) -> String {
        guard let raw = rawValue else { return "\u{2014}" }
        if let mapped = valueMap?.mappedText(for: raw) {
            return "\(mapped) (\(raw))"
        }
        if let numeric = Double(raw) {
            return ZabbixValueFormatting.formatItemValue(numeric, units: units, decimalPlaces: decimalPlaces)
        }
        return raw
    }

    /// Like `formattedItemValue`, but with Zabbix's default `convert_units` precision — trimmed
    /// 2 fractional digits when a K/M/G/T prefix is applied, 4 significant fractional digits when
    /// not — for widgets that have no decimal-places setting (Data overview, Item history).
    static func formattedDefaultValue(rawValue: String?, units: String, valueMap: ZabbixValueMap?) -> String {
        guard let raw = rawValue else { return "\u{2014}" }
        if let mapped = valueMap?.mappedText(for: raw) {
            return "\(mapped) (\(raw))"
        }
        if let numeric = Double(raw) {
            return ZabbixValueFormatting.formatDefault(numeric, units: units)
        }
        return raw
    }

    /// Returns the value of a scalar widget field, e.g. "min" or "show_lines".
    static func fieldValue(_ fields: [ZabbixWidgetField], name: String) -> String? {
        fields.first { $0.name == name }?.value
    }

    /// The color of the highest `thresholds.N` band the reading meets or exceeds, or nil when the
    /// reading is below every threshold (or none are configured). This is Zabbix's value-driven
    /// alert color — the same `thresholds.N.threshold`/`.color` fields the gauge arc uses — so a
    /// value crossing a threshold repaints the item-value background.
    static func thresholdColorHex(for value: Double?, fields: [ZabbixWidgetField]) -> String? {
        guard let value else { return nil }
        return indexedFieldGroups(fields, prefix: "thresholds")
            .compactMap { group -> (threshold: Double, color: String)? in
                guard let threshold = group["threshold"].flatMap(Double.init), let color = group["color"] else {
                    return nil
                }
                return (threshold, color)
            }
            .sorted { $0.threshold < $1.threshold }
            .last { value >= $0.threshold }?
            .color
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

    /// The worst active-problem severity for a map element, by its type: hosts (0) use their host's
    /// severity, triggers (2) the worst of their referenced triggers, host groups (3) the worst
    /// across the group's hosts. Submap (1) and image (4) elements have no computed severity here
    /// (submap rollup would require recursively resolving the child map), so they stay at 0/OK.
    static func mapElementSeverity(
        elementType: Int,
        references: [ZabbixMapElementReference],
        severityByHostID: [String: Int],
        severityByTriggerID: [String: Int],
        severityByGroupID: [String: Int]
    ) -> Int {
        switch elementType {
        case 0: return references.compactMap { $0.hostid.flatMap { severityByHostID[$0] } }.max() ?? 0
        case 2: return references.compactMap { $0.triggerid.flatMap { severityByTriggerID[$0] } }.max() ?? 0
        case 3: return references.compactMap { $0.groupid.flatMap { severityByGroupID[$0] } }.max() ?? 0
        default: return 0
        }
    }

    /// Human-readable label for an HA node status (0 = standby, 1 = stopped, 2 = unavailable,
    /// 3 = active).
    static func haNodeStatusLabel(_ status: Int) -> String {
        switch status {
        case 0: return "Standby"
        case 1: return "Stopped"
        case 2: return "Unavailable"
        case 3: return "Active"
        default: return "Unknown"
        }
    }

    /// Whether the Zabbix server is running, inferred from HA node statuses: up when any node is
    /// active (3). Returns nil when there are no nodes (standalone/older server), so the caller can
    /// fall back to the API-success proxy rather than reporting the server down.
    static func isServerRunning(fromHANodeStatuses statuses: [Int]) -> Bool? {
        statuses.isEmpty ? nil : statuses.contains(3)
    }

    /// Parses the Geomap widget's `default_view` — Zabbix stores it as "latitude,longitude,zoom" —
    /// into a `GeoMapView`. Returns nil for an empty/malformed value so the caller falls back to
    /// auto-fitting the markers.
    static func parseGeoMapDefaultView(_ raw: String?) -> GeoMapView? {
        guard let raw, !raw.isEmpty else { return nil }
        let parts = raw.split(separator: ",").map { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard parts.count == 3, let latitude = parts[0], let longitude = parts[1], let zoom = parts[2] else {
            return nil
        }
        return GeoMapView(latitude: latitude, longitude: longitude, zoom: zoom)
    }

    /// The Clock widget's configured display timezone (`tzone_timezone`), or nil to use the device's
    /// local zone. Zabbix's "local"/"system" sentinels (and an empty value) all mean local.
    static func clockTimeZoneIdentifier(from fields: [ZabbixWidgetField]) -> String? {
        guard let value = fieldValue(fields, name: "tzone_timezone"), !value.isEmpty else { return nil }
        return (value == "local" || value == "system") ? nil : value
    }

    /// Seconds to add to the device clock to read as a host's own time, from its `system.localtime`
    /// item: the host's reported time (`lastvalue`, a Unix timestamp) minus when it was collected
    /// (`lastclock`). Nil when either is missing or non-numeric, so the caller falls back to local.
    static func hostTimeOffset(lastValue: String?, lastClock: String?) -> TimeInterval? {
        guard let reported = lastValue.flatMap(Double.init), let collected = lastClock.flatMap(Double.init) else {
            return nil
        }
        return reported - collected
    }

    /// Maps the Problems widget's `acknowledgement_status` (0 = all, 1 = unacknowledged, 2 =
    /// acknowledged) to a `problem.get` `acknowledged` filter. An absent or unrecognized value means
    /// no filter (every problem), preserving prior behavior when the widget doesn't set the option.
    static func problemsAcknowledgedFilter(from fields: [ZabbixWidgetField]) -> Bool? {
        switch fieldValue(fields, name: "acknowledgement_status").flatMap(Int.init) {
        case 1: return false
        case 2: return true
        default: return nil
        }
    }

    /// Maps the Problems-by-severity widget's `ext_ack` (0 = all, 1 = unacknowledged only, 2 =
    /// separated display) to a `problem.get` `acknowledged` filter. Only "unacknowledged only"
    /// restricts the counts; "all" and the separated-display mode leave every problem in.
    static func severityAcknowledgedFilter(from fields: [ZabbixWidgetField]) -> Bool? {
        fieldValue(fields, name: "ext_ack").flatMap(Int.init) == 1 ? false : nil
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
