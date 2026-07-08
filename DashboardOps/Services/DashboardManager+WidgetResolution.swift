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
        let problems = try await zabbixAPIClient.problems(serverBaseURL: serverBaseURL, authToken: authToken)
        let triggerIDs = Array(Set(problems.map(\.objectid)))
        let triggerHosts = try await zabbixAPIClient.triggerHosts(serverBaseURL: serverBaseURL, authToken: authToken, triggerIDs: triggerIDs)
        let hostIDByTriggerID = Dictionary(uniqueKeysWithValues: triggerHosts.map { ($0.triggerid, $0.hosts.first?.hostid) })

        let hostIDs = Array(Set(problems.compactMap { hostIDByTriggerID[$0.objectid] ?? nil }))
        let hostGroups = try await zabbixAPIClient.hostGroups(serverBaseURL: serverBaseURL, authToken: authToken, hostIDs: hostIDs)
        let groupsByHostID = Dictionary(uniqueKeysWithValues: hostGroups.map { ($0.hostid, $0.hostgroups) })

        var summaryByGroup: [String: (name: String, count: Int, maxSeverity: Int)] = [:]

        for problem in problems {
            guard let hostID = hostIDByTriggerID[problem.objectid] ?? nil,
                  let groups = groupsByHostID[hostID] else {
                continue
            }

            for group in groups {
                var summary = summaryByGroup[group.groupid] ?? (name: group.name, count: 0, maxSeverity: 0)
                summary.count += 1
                summary.maxSeverity = max(summary.maxSeverity, problem.severity.intValue)
                summaryByGroup[group.groupid] = summary
            }
        }

        return .problemsByHostGroup(
            summaryByGroup.map { groupID, summary in
                HostGroupProblemSummary(id: groupID, groupName: summary.name, count: summary.count, maxSeverity: summary.maxSeverity)
            }.sorted { $0.maxSeverity == $1.maxSeverity ? $0.count > $1.count : $0.maxSeverity > $1.maxSeverity }
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

    // MARK: - Shared helpers

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
