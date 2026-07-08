//
//  DashboardManager+WidgetResolution.swift
//  DashboardOps
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
    func resolveWidgetKind(
        _ widget: ZabbixWidget,
        serverBaseURL: URL,
        authToken: String
    ) async throws -> DashboardWidgetKind {
        switch widget.type {
        case "clock":
            return .clock

        case "problems":
            let severities = Self.indexedValues(widget.fields, name: "severities").compactMap(Int.init)

            let problems = try await zabbixAPIClient.problems(
                serverBaseURL: serverBaseURL,
                authToken: authToken,
                severities: severities.isEmpty ? nil : severities
            )

            let hostByTriggerID = try await hostNamesByTriggerID(
                problems.map(\.objectid),
                serverBaseURL: serverBaseURL,
                authToken: authToken
            )

            return .problems(
                problems.map { problem in
                    DashboardProblem(
                        id: problem.eventid,
                        name: problem.name,
                        severity: problem.severity.intValue,
                        host: hostByTriggerID[problem.objectid],
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

            return .itemValue(name: item.name, value: item.lastvalue ?? "\u{2014}", units: item.units ?? "")

        case "problemsbysv":
            let problems = try await zabbixAPIClient.problems(serverBaseURL: serverBaseURL, authToken: authToken)
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

            let hosts = try await zabbixAPIClient.hostsWithInterfaces(serverBaseURL: serverBaseURL, authToken: authToken)

            return .hostAvailability(
                requestedTypes.sorted().map { type in
                    var available = 0
                    var unavailable = 0
                    var unknown = 0

                    for interface in hosts.flatMap(\.interfaces) where interface.type.intValue == type {
                        switch interface.available.intValue {
                        case 1: available += 1
                        case 2: unavailable += 1
                        default: unknown += 1
                        }
                    }

                    return HostInterfaceAvailability(
                        interfaceTypeName: Self.interfaceTypeName(type),
                        available: available,
                        unavailable: unavailable,
                        unknown: unknown
                    )
                }
            )

        case "systeminfo":
            async let hostCount = zabbixAPIClient.hostCount(serverBaseURL: serverBaseURL, authToken: authToken)
            async let itemCount = zabbixAPIClient.itemCount(serverBaseURL: serverBaseURL, authToken: authToken)
            async let problemCount = zabbixAPIClient.problemCount(serverBaseURL: serverBaseURL, authToken: authToken)

            return try await .systemOverview(hostCount: hostCount, itemCount: itemCount, problemCount: problemCount)

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
            return try await resolveProblemHosts(serverBaseURL: serverBaseURL, authToken: authToken)

        case "actionlog":
            return try await resolveActionLog(serverBaseURL: serverBaseURL, authToken: authToken)

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
            GaugeReading(name: item.name, value: value, minValue: minValue, maxValue: maxValue, units: item.units ?? "", thresholds: thresholds)
        )
    }

    // MARK: - Honeycomb

    /// The "itempatterns.N.itemname" field name is Zabbix's documented honeycomb configuration
    /// option, not yet verified against a live example.
    private func resolveHoneycomb(
        _ widget: ZabbixWidget,
        serverBaseURL: URL,
        authToken: String
    ) async throws -> DashboardWidgetKind {
        let groupIDs = Self.indexedValues(widget.fields, name: "groupids")
        let hostIDs = Self.indexedValues(widget.fields, name: "hostids")
        let namePattern = Self.indexedFieldGroups(widget.fields, prefix: "itempatterns").first?["itemname"]

        let items = try await zabbixAPIClient.itemsMatching(
            serverBaseURL: serverBaseURL,
            authToken: authToken,
            groupIDs: groupIDs.isEmpty ? nil : groupIDs,
            hostIDs: hostIDs.isEmpty ? nil : hostIDs,
            namePattern: namePattern
        )

        return .honeycomb(
            items.prefix(60).map { item in
                HoneycombCell(
                    id: item.itemid,
                    primaryLabel: item.hosts.first?.name ?? "",
                    secondaryLabel: item.name,
                    value: item.lastvalue ?? "\u{2014}"
                )
            }
        )
    }

    // MARK: - Top hosts

    /// Resolves at most 25 hosts, each requiring one item lookup per configured column, to bound
    /// round trips on a TV with limited compute/network. Column field names ("columns.N.name",
    /// "columns.N.item", "columns.N.text") are Zabbix's documented options, not yet verified.
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

        var rows: [TopHostsRow] = []
        for host in hosts.prefix(25) {
            guard !columnGroups.isEmpty else {
                rows.append(TopHostsRow(id: host.hostid, hostName: host.name, values: [host.name]))
                continue
            }

            var values: [String] = []
            for column in columnGroups {
                if let itemPattern = column["item"], !itemPattern.isEmpty {
                    let items = try await zabbixAPIClient.itemsMatching(
                        serverBaseURL: serverBaseURL,
                        authToken: authToken,
                        hostIDs: [host.hostid],
                        namePattern: itemPattern
                    )
                    values.append(items.first?.lastvalue ?? "\u{2014}")
                } else if let text = column["text"] {
                    values.append(text)
                } else {
                    values.append(host.name)
                }
            }
            rows.append(TopHostsRow(id: host.hostid, hostName: host.name, values: values))
        }

        return .topHosts(columns: columnTitles, rows: rows)
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
            severities: severities.isEmpty ? nil : severities
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
        let groupIDs = Self.indexedValues(widget.fields, name: "groupids")
        let hostIDs = Self.indexedValues(widget.fields, name: "hostids")

        let triggers = try await zabbixAPIClient.activeTriggers(
            serverBaseURL: serverBaseURL,
            authToken: authToken,
            groupIDs: groupIDs.isEmpty ? nil : groupIDs,
            hostIDs: hostIDs.isEmpty ? nil : hostIDs
        )

        var rowsByHostID: [String: TriggerOverviewRow] = [:]
        var hostOrder: [String] = []

        for trigger in triggers {
            guard let host = trigger.hosts.first else { continue }
            let indicator = TriggerIndicator(id: trigger.triggerid, name: trigger.description, severity: trigger.priority.intValue)

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

    private func resolveProblemHosts(serverBaseURL: URL, authToken: String) async throws -> DashboardWidgetKind {
        let resolved = try await activeProblemsWithHostID(serverBaseURL: serverBaseURL, authToken: authToken)
        let hostIDs = Array(Set(resolved.map(\.hostID)))
        let hostGroups = try await zabbixAPIClient.hostGroups(serverBaseURL: serverBaseURL, authToken: authToken, hostIDs: hostIDs)
        let groupsByHostID = Dictionary(uniqueKeysWithValues: hostGroups.map { ($0.hostid, $0.hostgroups) })

        var summaryByGroup: [String: (name: String, count: Int, maxSeverity: Int)] = [:]

        for entry in resolved {
            guard let groups = groupsByHostID[entry.hostID] else { continue }

            for group in groups {
                var summary = summaryByGroup[group.groupid] ?? (name: group.name, count: 0, maxSeverity: 0)
                summary.count += 1
                summary.maxSeverity = max(summary.maxSeverity, entry.problem.severity.intValue)
                summaryByGroup[group.groupid] = summary
            }
        }

        return .problemsByHostGroup(
            summaryByGroup.map { groupID, summary in
                HostGroupProblemSummary(id: groupID, groupName: summary.name, count: summary.count, maxSeverity: summary.maxSeverity)
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

        let hostIDs = map.selements.compactMap { $0.elementtype.intValue == 0 ? $0.elements.first?.hostid : nil }
        let hosts = try await zabbixAPIClient.hosts(serverBaseURL: serverBaseURL, authToken: authToken, hostIDs: hostIDs.isEmpty ? nil : hostIDs)
        let hostNameByID = Dictionary(uniqueKeysWithValues: hosts.map { ($0.hostid, $0.name) })
        let severityByHostID = try await maxSeverityByHostID(serverBaseURL: serverBaseURL, authToken: authToken)

        let activeTriggerIDs = Set(try await zabbixAPIClient.problems(serverBaseURL: serverBaseURL, authToken: authToken).map(\.objectid))

        var severityByElementID: [String: Int] = [:]
        let elements = map.selements.map { selement -> NetworkMapElement in
            let hostID = selement.elementtype.intValue == 0 ? selement.elements.first?.hostid : nil
            let label = hostID.flatMap { hostNameByID[$0] } ?? Self.cleanedMapLabel(selement.label)
            let severity = hostID.flatMap { severityByHostID[$0] } ?? 0
            severityByElementID[selement.selementid] = severity

            return NetworkMapElement(id: selement.selementid, label: label, x: selement.x.intValue, y: selement.y.intValue, severity: severity)
        }

        let elementsByID = Dictionary(uniqueKeysWithValues: elements.map { ($0.id, $0) })
        let links = map.links.compactMap { link -> NetworkMapLink? in
            guard let from = elementsByID[link.selementid1], let to = elementsByID[link.selementid2] else {
                return nil
            }
            let overrideColor = link.linktriggers.first { activeTriggerIDs.contains($0.triggerid) }?.color

            return NetworkMapLink(id: link.linkid, fromX: from.x, fromY: from.y, toX: to.x, toY: to.y, colorHex: overrideColor ?? link.color)
        }

        return .networkMap(NetworkMapDiagram(width: map.width.intValue, height: map.height.intValue, elements: elements, links: links))
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
        let groupIDs = Self.indexedValues(widget.fields, name: "groupids")
        let hostIDs = Self.indexedValues(widget.fields, name: "hostids")

        let hosts = try await zabbixAPIClient.hosts(
            serverBaseURL: serverBaseURL,
            authToken: authToken,
            groupIDs: groupIDs.isEmpty ? nil : groupIDs,
            hostIDs: hostIDs.isEmpty ? nil : hostIDs
        )

        let resolved = try await activeProblemsWithHostID(serverBaseURL: serverBaseURL, authToken: authToken)
        var countByHostID: [String: Int] = [:]
        var maxSeverityByHostID: [String: Int] = [:]
        for entry in resolved {
            countByHostID[entry.hostID, default: 0] += 1
            maxSeverityByHostID[entry.hostID] = max(maxSeverityByHostID[entry.hostID] ?? 0, entry.problem.severity.intValue)
        }

        return .hostList(
            hosts.prefix(100).map { host in
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
        let namePattern = Self.fieldValue(widget.fields, name: "item")

        let items = try await zabbixAPIClient.itemsMatching(
            serverBaseURL: serverBaseURL,
            authToken: authToken,
            groupIDs: groupIDs.isEmpty ? nil : groupIDs,
            hostIDs: hostIDs.isEmpty ? nil : hostIDs,
            namePattern: namePattern
        )

        return .itemList(
            items.prefix(100).map { item in
                ItemListEntry(
                    id: item.itemid,
                    name: item.name,
                    hostName: item.hosts.first?.name ?? "",
                    lastValue: item.lastvalue ?? "\u{2014}",
                    units: item.units ?? ""
                )
            }
        )
    }

    // MARK: - SLA report

    /// Shows each SLA's configured target only, not a computed period report — see
    /// `ZabbixSLA`'s documentation for why.
    private func resolveSLAReport(
        _ widget: ZabbixWidget,
        serverBaseURL: URL,
        authToken: String
    ) async throws -> DashboardWidgetKind {
        let slaID = Self.fieldValue(widget.fields, name: "slaid")
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
    private func resolveActionLog(serverBaseURL: URL, authToken: String) async throws -> DashboardWidgetKind {
        let sinceUnixTime = Int(Date().timeIntervalSince1970) - 7 * 24 * 3600
        let alerts = try await zabbixAPIClient.alerts(serverBaseURL: serverBaseURL, authToken: authToken, sinceUnixTime: sinceUnixTime)

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
        let itemIDs = Self.indexedValues(widget.fields, name: "itemids")
        guard !itemIDs.isEmpty else {
            return .unsupported(rawType: widget.type)
        }

        let items = try await zabbixAPIClient.items(serverBaseURL: serverBaseURL, authToken: authToken, itemIDs: itemIDs)

        var series: [ItemHistorySeries] = []
        for item in items {
            let historyValueType = item.value_type?.intValue ?? 0
            let values = try await zabbixAPIClient.history(
                serverBaseURL: serverBaseURL,
                authToken: authToken,
                itemID: item.itemid,
                historyValueType: historyValueType,
                sinceUnixTime: Int(Date().timeIntervalSince1970) - Self.defaultHistoryWindowSeconds,
                limit: 5
            )

            series.append(
                ItemHistorySeries(
                    id: item.itemid,
                    itemName: item.name,
                    units: item.units ?? "",
                    values: values.map { value in
                        ItemHistoryPoint(
                            id: "\(item.itemid).\(value.clock)",
                            value: value.value,
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

        let items = try await zabbixAPIClient.itemsMatching(
            serverBaseURL: serverBaseURL,
            authToken: authToken,
            groupIDs: groupIDs.isEmpty ? nil : groupIDs,
            hostIDs: hostIDs.isEmpty ? nil : hostIDs
        )

        return .dataOverview(
            items.prefix(100).map { item in
                DataOverviewEntry(
                    id: item.itemid,
                    hostName: item.hosts.first?.name ?? "",
                    itemName: item.name,
                    value: item.lastvalue ?? "\u{2014}",
                    units: item.units ?? ""
                )
            }
        )
    }

    // MARK: - SVG graph

    /// Dataset fields ("ds.N.hosts.0", "ds.N.items.0", "ds.N.color") verified against a live
    /// Zabbix 7.0 server. Only the first host/item pair per dataset is resolved; svggraph datasets
    /// can in principle aggregate multiple hosts or items per line, which isn't implemented here.
    private func resolveSVGGraph(
        _ widget: ZabbixWidget,
        serverBaseURL: URL,
        authToken: String
    ) async throws -> DashboardWidgetKind {
        let datasets = Self.indexedFieldGroups(widget.fields, prefix: "ds")
        guard !datasets.isEmpty else {
            return .unsupported(rawType: widget.type)
        }

        var series: [ChartSeries] = []
        for dataset in datasets {
            guard let hostName = dataset["hosts.0"], let itemPattern = dataset["items.0"] else { continue }

            let hosts = try await zabbixAPIClient.hostsByName(serverBaseURL: serverBaseURL, authToken: authToken, names: [hostName])
            guard let host = hosts.first else { continue }

            let items = try await zabbixAPIClient.itemsMatching(
                serverBaseURL: serverBaseURL,
                authToken: authToken,
                hostIDs: [host.hostid],
                namePattern: itemPattern
            )
            guard let item = items.first else { continue }

            let points = try await recentPoints(for: item.itemid, valueType: item.value_type?.intValue ?? 0, serverBaseURL: serverBaseURL, authToken: authToken)

            series.append(
                ChartSeries(
                    id: "\(widget.widgetid).\(item.itemid)",
                    name: "\(host.name): \(item.name)",
                    colorHex: dataset["color"] ?? "3DC9B0",
                    points: points
                )
            )
        }

        return series.isEmpty ? .unsupported(rawType: widget.type) : .lineChart(series)
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

        var series: [ChartSeries] = []
        for gitem in graph.gitems {
            guard let item = itemsByID[gitem.itemid] else { continue }

            let points = try await recentPoints(for: item.itemid, valueType: item.value_type?.intValue ?? 0, serverBaseURL: serverBaseURL, authToken: authToken)

            series.append(ChartSeries(id: "\(widget.widgetid).\(item.itemid)", name: item.name, colorHex: gitem.color, points: points))
        }

        return series.isEmpty ? .unsupported(rawType: widget.type) : .lineChart(series)
    }

    // MARK: - Pie chart

    /// Reuses the same "ds.N.*" dataset fields as svggraph (Zabbix's newer chart widgets share the
    /// dataset concept), showing each dataset's latest value rather than its history.
    private func resolvePieChart(
        _ widget: ZabbixWidget,
        serverBaseURL: URL,
        authToken: String
    ) async throws -> DashboardWidgetKind {
        let datasets = Self.indexedFieldGroups(widget.fields, prefix: "ds")
        guard !datasets.isEmpty else {
            return .unsupported(rawType: widget.type)
        }

        var slices: [ChartSlice] = []
        for dataset in datasets {
            guard let hostName = dataset["hosts.0"], let itemPattern = dataset["items.0"] else { continue }

            let hosts = try await zabbixAPIClient.hostsByName(serverBaseURL: serverBaseURL, authToken: authToken, names: [hostName])
            guard let host = hosts.first else { continue }

            let items = try await zabbixAPIClient.itemsMatching(
                serverBaseURL: serverBaseURL,
                authToken: authToken,
                hostIDs: [host.hostid],
                namePattern: itemPattern
            )
            guard let item = items.first, let value = item.lastvalue.flatMap(Double.init) else { continue }

            slices.append(ChartSlice(id: "\(widget.widgetid).\(item.itemid)", name: "\(host.name): \(item.name)", colorHex: dataset["color"] ?? "3DC9B0", value: value))
        }

        return slices.isEmpty ? .unsupported(rawType: widget.type) : .pieChart(slices)
    }

    // MARK: - Shared helpers

    /// Fetches an item's recent history, bounded to the last 24 hours to avoid the timeout an
    /// unbounded `history.get` call risks against a server with a large history table.
    private func recentPoints(
        for itemID: String,
        valueType: Int,
        serverBaseURL: URL,
        authToken: String
    ) async throws -> [ChartPoint] {
        let values = try await zabbixAPIClient.history(
            serverBaseURL: serverBaseURL,
            authToken: authToken,
            itemID: itemID,
            historyValueType: valueType,
            sinceUnixTime: Int(Date().timeIntervalSince1970) - Self.defaultHistoryWindowSeconds,
            limit: 200
        )

        return values.reversed().compactMap { value in
            guard let doubleValue = Double(value.value), let timestamp = TimeInterval(value.clock) else {
                return nil
            }
            return ChartPoint(id: "\(itemID).\(value.clock)", date: Date(timeIntervalSince1970: timestamp), value: doubleValue)
        }
    }

    private static let defaultHistoryWindowSeconds = 24 * 3600

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
        authToken: String
    ) async throws -> [(problem: ZabbixProblemSummary, hostID: String)] {
        let problems = try await zabbixAPIClient.problems(serverBaseURL: serverBaseURL, authToken: authToken)
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

    /// Returns the value of a scalar widget field, e.g. "min" or "show_lines".
    static func fieldValue(_ fields: [ZabbixWidgetField], name: String) -> String? {
        fields.first { $0.name == name }?.value
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
}
