//
//  ZabbixAPIParameters.swift
//  ZabbixAppleTVDashboard
//
//  Created by Codex on 7/7/26.
//

import Foundation

/// Empty object parameters for Zabbix methods that accept no object fields.
nonisolated struct ZabbixEmptyObjectParameters: Encodable, Sendable {}

/// Parameters for `settings.get` requesting only the trigger severity color/name fields.
nonisolated struct ZabbixSeverityPaletteParameters: Encodable, Sendable {
    let output: [String] = [
        "severity_color_0", "severity_color_1", "severity_color_2",
        "severity_color_3", "severity_color_4", "severity_color_5",
        "severity_name_0", "severity_name_1", "severity_name_2",
        "severity_name_3", "severity_name_4", "severity_name_5",
        "blink_period",
    ]
}

/// Login parameters for `user.login`.
nonisolated struct ZabbixLoginParameters: Encodable, Sendable {
    /// Zabbix username.
    let username: String

    /// Zabbix password.
    let password: String
}

/// Parameters for `dashboard.get`.
nonisolated struct ZabbixDashboardGetParameters: Encodable, Sendable {
    /// Dashboard fields to return.
    let output: [String]

    init(output: [String] = ["dashboardid", "name"]) {
        self.output = output
    }
}

/// Parameters for `dashboard.get` when fetching a single dashboard's full widget layout.
nonisolated struct ZabbixDashboardGetDetailParameters: Encodable, Sendable {
    /// Dashboard identifier to fetch.
    let dashboardids: [String]

    /// Requests each page's widgets and their configuration fields.
    let selectPages: String

    init(dashboardID: String, selectPages: String = "extend") {
        self.dashboardids = [dashboardID]
        self.selectPages = selectPages
    }
}

/// Parameters for `item.get`.
nonisolated struct ZabbixItemGetParameters: Encodable, Sendable {
    /// Item identifiers to fetch.
    let itemids: [String]

    /// Item fields to return.
    let output: [String]

    /// Requests each item's value map (its `mappings`), so a raw reading can be shown as its label
    /// (e.g. "Up (1)") the way Zabbix's own item-value and gauge widgets do.
    let selectValueMap: [String]

    /// Requests each item's host, so label-macro templates like "{HOST.NAME}" (item value / gauge
    /// `description`) can resolve.
    let selectHosts: [String]

    init(itemIDs: [String], output: [String] = ["itemid", "name", "lastvalue", "prevvalue", "lastclock", "units", "value_type"], selectValueMap: [String] = ["mappings"], selectHosts: [String] = ["hostid", "name"]) {
        self.itemids = itemIDs
        self.output = output
        self.selectValueMap = selectValueMap
        self.selectHosts = selectHosts
    }
}

/// A single tag filter for problem/trigger/host/item queries, mirroring a widget's `tags.N.*`
/// configuration. `operator` uses Zabbix's shared tag-operator enum: 0 = Contains, 1 = Equals,
/// 2 = Does not contain, 3 = Does not equal, 4 = Exists, 5 = Does not exist. The same struct is
/// accepted by every `*.get` method that supports a `tags` array, so one builder scopes them all.
nonisolated struct ZabbixTagFilter: Encodable, Sendable {
    let tag: String
    let value: String
    let `operator`: Int
}

/// Parameters for `problem.get`.
///
/// `problem.get` does not support `selectHosts` (verified against a live Zabbix 7.0 server) —
/// hosts are resolved separately via `trigger.get` using each problem's `objectid`.
nonisolated struct ZabbixProblemGetParameters: Encodable, Sendable {
    /// Problem fields to return.
    let output: [String]

    /// Severities to include, matching the "problems" widget's own `severities.N` fields. Omitted
    /// (all severities included) when the widget doesn't filter by severity.
    let severities: [Int]?

    /// Host groups to include, matching the widget's positive `groupids.N` scope (already expanded
    /// to nested subgroups by the caller). Omitted (all groups) when the widget isn't group-scoped.
    let groupids: [String]?

    /// Field to sort results by.
    let sortfield: [String]

    /// Sort order for `sortfield`.
    let sortorder: String

    /// Maximum number of problems to return. Most callers use this to compute a current-state
    /// summary (severity tallies, per-host-group counts, map/marker coloring) rather than a
    /// capped display list, so it needs to comfortably cover a genuinely bad day, not just a
    /// small sample — verified live against this server during a busy period: 1,036 concurrent
    /// active problems, which a small default (originally 20, matching Zabbix's own API default)
    /// silently truncated to under 2% of the real count, with no error or indication anything was
    /// missing. Callers that do want a short, admin-configured list (e.g. the "Problems" widget's
    /// own "show_lines" field) pass their own explicit `limit`.
    let limit: Int

    /// Suppression filter, matching Zabbix's own "Show suppressed problems" widget option. `false`
    /// returns only unsuppressed problems (Zabbix's default across its problem widgets — a host in
    /// maintenance or a manually-suppressed problem is hidden); `true` returns only suppressed;
    /// `nil` omits the filter so every problem is returned regardless of suppression. Without this,
    /// the app counted suppressed problems the real widgets hide, inflating severity tallies well
    /// above what the same dashboard shows in Zabbix.
    let suppressed: Bool?

    /// The widget's own tag filter (from its `tags.N.*` fields). Omitted when empty so an unfiltered
    /// query is unchanged.
    let tags: [ZabbixTagFilter]?

    /// Tag evaluation type (`evaltype`): 0 = And/Or, 2 = Or. Only meaningful — and only sent —
    /// alongside a non-empty `tags`.
    let evaltype: Int?

    /// Acknowledgement filter, matching the problem widgets' own acknowledgement option. `false`
    /// returns only unacknowledged problems, `true` only acknowledged, `nil` omits the filter so
    /// every problem is returned regardless. Without this the app counted acknowledged problems a
    /// widget scoped to "unacknowledged only" would hide, inflating its counts.
    let acknowledged: Bool?

    init(
        output: [String] = ["eventid", "name", "severity", "clock", "objectid"],
        severities: [Int]? = nil,
        groupids: [String]? = nil,
        sortfield: [String] = ["eventid"],
        sortorder: String = "DESC",
        limit: Int = 5000,
        suppressed: Bool? = false,
        tags: [ZabbixTagFilter]? = nil,
        evaltype: Int? = nil,
        acknowledged: Bool? = nil
    ) {
        self.output = output
        self.severities = severities
        self.groupids = (groupids?.isEmpty == false) ? groupids : nil
        self.sortfield = sortfield
        self.sortorder = sortorder
        self.limit = limit
        self.suppressed = suppressed
        self.tags = (tags?.isEmpty == false) ? tags : nil
        self.evaltype = (tags?.isEmpty == false) ? evaltype : nil
        self.acknowledged = acknowledged
    }

    private enum CodingKeys: String, CodingKey {
        case output, severities, groupids, sortfield, sortorder, limit, suppressed, tags, evaltype, acknowledged, selectTags
    }

    /// Always request each problem's event tags, so the problems widget can show them per its
    /// `show_tags` option. Other callers (severity tallies, counts) simply ignore them.
    private static let selectTagsFields = ["tag", "value"]

    // Custom encoding so a `nil` optional is omitted entirely rather than sent as JSON `null`:
    // omitting `suppressed`/`acknowledged` is how "return problems regardless of that status" is
    // expressed, and omitting `severities`/`groupids`/`tags` cleanly means "no such filter".
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(output, forKey: .output)
        try container.encodeIfPresent(severities, forKey: .severities)
        try container.encodeIfPresent(groupids, forKey: .groupids)
        try container.encode(sortfield, forKey: .sortfield)
        try container.encode(sortorder, forKey: .sortorder)
        try container.encode(limit, forKey: .limit)
        try container.encodeIfPresent(suppressed, forKey: .suppressed)
        try container.encodeIfPresent(tags, forKey: .tags)
        try container.encodeIfPresent(evaltype, forKey: .evaltype)
        try container.encodeIfPresent(acknowledged, forKey: .acknowledged)
        try container.encode(Self.selectTagsFields, forKey: .selectTags)
    }
}

/// Parameters for `trigger.get` when resolving the hosts a set of triggers belong to.
nonisolated struct ZabbixTriggerGetParameters: Encodable, Sendable {
    /// Trigger identifiers to resolve.
    let triggerids: [String]

    /// Trigger fields to return.
    let output: [String]

    /// Requests each trigger's associated hosts.
    let selectHosts: [String]

    init(triggerIDs: [String], output: [String] = ["triggerid"], selectHosts: [String] = ["name"]) {
        self.triggerids = triggerIDs
        self.output = output
        self.selectHosts = selectHosts
    }
}

/// Filters `host.get`/`item.get` to enabled objects only.
nonisolated struct ZabbixEnabledFilter: Encodable, Sendable {
    /// 0 = enabled, matching Zabbix's own status convention.
    let status = 0
}

/// Parameters for `host.get` when resolving interface availability for the "hostavail" widget.
nonisolated struct ZabbixHostAvailabilityParameters: Encodable, Sendable {
    /// Host fields to return.
    let output: [String]

    /// Requests each host's interfaces with their type and availability.
    let selectInterfaces: [String]

    /// Host groups to include, matching the widget's `groupids.N` scope (already expanded to nested
    /// subgroups). Omitted (whole server counted) when the widget isn't group-scoped.
    let groupids: [String]?

    /// Restricts results to enabled hosts.
    let filter: ZabbixEnabledFilter

    init(output: [String] = ["hostid"], selectInterfaces: [String] = ["type", "available"], groupIDs: [String]? = nil) {
        self.output = output
        self.selectInterfaces = selectInterfaces
        self.groupids = (groupIDs?.isEmpty == false) ? groupIDs : nil
        self.filter = ZabbixEnabledFilter()
    }

    private enum CodingKeys: String, CodingKey { case output, selectInterfaces, groupids, filter }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(output, forKey: .output)
        try container.encode(selectInterfaces, forKey: .selectInterfaces)
        try container.encodeIfPresent(groupids, forKey: .groupids)
        try container.encode(filter, forKey: .filter)
    }
}

/// Parameters for `trigger.get` when fetching currently active (problem-state) triggers.
nonisolated struct ZabbixActiveTriggerGetParameters: Encodable, Sendable {
    /// Trigger fields to return.
    let output: [String]

    /// Requests each trigger's host.
    let selectHosts: [String]

    /// Restricts to hosts in these groups, when the widget filters by host group.
    let groupids: [String]?

    /// Restricts to these hosts, when the widget filters by specific hosts.
    let hostids: [String]?

    /// When `true`, restricts to triggers currently in the PROBLEM state (`filter: {value: 1}`).
    /// When `false`, every trigger is returned so the overview can render OK (green) cells too,
    /// which the widget's "Show: Any" option calls for.
    let onlyProblems: Bool

    /// The widget's own tag filter (from its `tags.N.*` fields); omitted when empty.
    let tags: [ZabbixTagFilter]?

    /// Tag evaluation type (`evaltype`): 0 = And/Or, 2 = Or. Only sent alongside a non-empty `tags`.
    let evaltype: Int?

    /// Maximum number of triggers to return.
    let limit: Int

    init(
        output: [String] = ["triggerid", "description", "priority", "value"],
        selectHosts: [String] = ["name"],
        groupids: [String]? = nil,
        hostids: [String]? = nil,
        onlyProblems: Bool = true,
        tags: [ZabbixTagFilter]? = nil,
        evaltype: Int? = nil,
        limit: Int = 100
    ) {
        self.output = output
        self.selectHosts = selectHosts
        self.groupids = groupids
        self.hostids = hostids
        self.onlyProblems = onlyProblems
        self.tags = (tags?.isEmpty == false) ? tags : nil
        self.evaltype = (tags?.isEmpty == false) ? evaltype : nil
        self.limit = limit
    }

    private enum CodingKeys: String, CodingKey {
        case output, selectHosts, groupids, hostids, filter, tags, evaltype, limit
    }

    // Custom encoding so the PROBLEM-state filter is present only when `onlyProblems` is set, and a
    // nil `groupids`/`hostids`/`tags` is omitted rather than sent as JSON `null`.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(output, forKey: .output)
        try container.encode(selectHosts, forKey: .selectHosts)
        try container.encodeIfPresent(groupids, forKey: .groupids)
        try container.encodeIfPresent(hostids, forKey: .hostids)
        if onlyProblems {
            try container.encode(ZabbixTriggerValueFilter(), forKey: .filter)
        }
        try container.encodeIfPresent(tags, forKey: .tags)
        try container.encodeIfPresent(evaltype, forKey: .evaltype)
        try container.encode(limit, forKey: .limit)
    }
}

/// Restricts `trigger.get` to triggers currently in the PROBLEM state.
nonisolated struct ZabbixTriggerValueFilter: Encodable, Sendable {
    let value = 1
}

/// Parameters for `host.get` when resolving the host groups a set of hosts belong to.
nonisolated struct ZabbixHostGroupLookupParameters: Encodable, Sendable {
    /// Host identifiers to resolve.
    let hostids: [String]

    /// Host fields to return.
    let output: [String]

    /// Requests each host's groups.
    let selectHostGroups: [String]

    init(hostIDs: [String], output: [String] = ["hostid", "name"], selectHostGroups: [String] = ["groupid", "name"]) {
        self.hostids = hostIDs
        self.output = output
        self.selectHostGroups = selectHostGroups
    }
}

/// Parameters for `hostgroup.get`. Resolves specific groups by ID, or all groups when `groupIDs`
/// is nil — used to expand a widget's selected groups to their nested subgroups by name, the way
/// Zabbix's own frontend does before it queries.
nonisolated struct ZabbixHostGroupGetParameters: Encodable, Sendable {
    let groupids: [String]?
    let output: [String]

    init(groupIDs: [String]? = nil, output: [String] = ["groupid", "name"]) {
        self.groupids = groupIDs
        self.output = output
    }

    private enum CodingKeys: String, CodingKey { case groupids, output }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(groupids, forKey: .groupids)
        try container.encode(output, forKey: .output)
    }
}

/// Parameters for `item.get` when resolving items by name pattern for a set of hosts, as used by
/// widgets that display item values keyed by host (top hosts, honeycomb, data overview).
nonisolated struct ZabbixItemSearchParameters: Encodable, Sendable {
    /// Restricts the search to these host groups, when specified.
    let groupids: [String]?

    /// Restricts the search to these hosts, when specified.
    let hostids: [String]?

    /// Item fields to return.
    let output: [String]

    /// Requests each item's host.
    let selectHosts: [String]

    /// Requests each item's value map, so widgets on this search path (data overview, top hosts,
    /// honeycomb, item navigator) can show mapped labels instead of raw codes.
    let selectValueMap: [String]

    /// Wildcard name search, e.g. "CPU load" or "CPU*".
    let search: ZabbixItemNameSearch?

    /// Enables "*" wildcard matching in `search` rather than plain substring matching.
    let searchWildcardsEnabled: Bool?

    /// The widget's item-tag filter (from its `tags.N.*` fields). `item.get` supports the same
    /// tag/operator/evaltype filtering as `problem.get`, so widgets on this search path (data
    /// overview, honeycomb, item navigator) can scope to tagged items instead of showing a
    /// tag-unfiltered superset. Omitted when empty so an unfiltered query is unchanged.
    let tags: [ZabbixTagFilter]?

    /// Tag evaluation type (`evaltype`): 0 = And/Or, 2 = Or. Only sent alongside a non-empty `tags`.
    let evaltype: Int?

    init(
        groupIDs: [String]? = nil,
        hostIDs: [String]? = nil,
        namePattern: String? = nil,
        tags: [ZabbixTagFilter]? = nil,
        evaltype: Int? = nil,
        output: [String] = ["itemid", "name", "lastvalue", "units", "value_type"],
        selectHosts: [String] = ["hostid", "name"],
        selectValueMap: [String] = ["mappings"]
    ) {
        self.groupids = groupIDs
        self.hostids = hostIDs
        self.output = output
        self.selectHosts = selectHosts
        self.selectValueMap = selectValueMap
        self.search = namePattern.map(ZabbixItemNameSearch.init)
        self.searchWildcardsEnabled = namePattern != nil ? true : nil
        self.tags = (tags?.isEmpty == false) ? tags : nil
        self.evaltype = (tags?.isEmpty == false) ? evaltype : nil
    }
}

/// Wildcard name filter for `item.get`.
nonisolated struct ZabbixItemNameSearch: Encodable, Sendable {
    let name: String
}

/// Parameters for `history.get` when fetching an item's recent values.
///
/// Always time-bounded: an unbounded `history.get` call risks the same timeout an unbounded
/// `alert.get` call hit against a live server with a large history table.
nonisolated struct ZabbixHistoryGetParameters: Encodable, Sendable {
    /// Zabbix value type: 0 = float, 1 = character, 2 = log, 3 = unsigned, 4 = text.
    let history: Int

    /// Item identifiers to fetch history for.
    let itemids: [String]

    /// Unix timestamp; only values at or after this time are returned.
    let time_from: Int

    /// Field to sort by.
    let sortfield: String

    /// Sort order.
    let sortorder: String

    /// Maximum number of values to return per item.
    let limit: Int

    init(
        historyValueType: Int,
        itemIDs: [String],
        sinceUnixTime: Int,
        sortfield: String = "clock",
        sortorder: String = "DESC",
        limit: Int = 100
    ) {
        self.history = historyValueType
        self.itemids = itemIDs
        self.time_from = sinceUnixTime
        self.sortfield = sortfield
        self.sortorder = sortorder
        self.limit = limit
    }
}

/// Parameters for `trend.get` when backfilling the older part of a graph window from hourly trend
/// data. Unlike `history.get`, `trend.get` needs no value-type parameter — it resolves the correct
/// trends table from the item itself.
nonisolated struct ZabbixTrendGetParameters: Encodable, Sendable {
    /// Item identifiers to fetch trends for.
    let itemids: [String]

    /// Unix timestamp; only trends at or after this time are returned.
    let time_from: Int

    /// Unix timestamp; only trends at or before this time are returned.
    let time_till: Int

    /// Trend fields to return.
    let output: [String]

    /// Maximum number of trend records to return.
    let limit: Int

    init(itemID: String, timeFrom: Int, timeTill: Int, output: [String] = ["clock", "value_min", "value_avg", "value_max"], limit: Int = 6000) {
        self.itemids = [itemID]
        self.time_from = timeFrom
        self.time_till = timeTill
        self.output = output
        self.limit = limit
    }
}

/// Parameters for `host.get` when resolving hosts by their exact technical name, as used by chart
/// widgets whose datasets reference a host by name rather than ID (e.g. "ds.0.hosts.0").
nonisolated struct ZabbixHostByNameParameters: Encodable, Sendable {
    /// Exact host technical names to resolve.
    let filter: ZabbixHostNameFilter

    /// Host fields to return.
    let output: [String]

    init(names: [String], output: [String] = ["hostid", "name"]) {
        self.filter = ZabbixHostNameFilter(host: names)
        self.output = output
    }
}

/// Exact host name filter for `host.get`.
nonisolated struct ZabbixHostNameFilter: Encodable, Sendable {
    let host: [String]
}

/// Parameters for `graph.get` when resolving a classic graph's member items.
nonisolated struct ZabbixGraphGetParameters: Encodable, Sendable {
    /// Graph identifiers to fetch.
    let graphids: [String]

    /// Graph fields to return.
    let output: [String]

    /// Requests each graph's member items and their configured colors.
    let selectGraphItems: [String]

    init(graphIDs: [String], output: [String] = ["graphid", "name", "graphtype"], selectGraphItems: [String] = ["itemid", "color"]) {
        self.graphids = graphIDs
        self.output = output
        self.selectGraphItems = selectGraphItems
    }
}

/// Parameters for `alert.get` when fetching recent notifications/remote commands for the action log widget.
///
/// Always time-bounded: an unbounded `alert.get` call timed out against a live server with years
/// of history, so a `time_from` is required rather than optional.
nonisolated struct ZabbixAlertGetParameters: Encodable, Sendable {
    /// Alert fields to return.
    let output: [String]

    /// Unix timestamp; only alerts at or after this time are returned.
    let time_from: Int

    /// Field to sort by.
    let sortfield: String

    /// Sort order.
    let sortorder: String

    /// Maximum number of alerts to return.
    let limit: Int

    /// The Action log widget's own content filters. Each is omitted when empty, so an unconfigured
    /// widget's query is unchanged. `statuses` is sent as `filter: {status: [...]}`; the rest map to
    /// `alert.get`'s array parameters of the same name.
    let actionids: [String]?
    let mediatypeids: [String]?
    let userids: [String]?
    let statuses: [Int]?

    init(
        sinceUnixTime: Int,
        actionIDs: [String]? = nil,
        mediatypeIDs: [String]? = nil,
        userIDs: [String]? = nil,
        statuses: [Int]? = nil,
        output: [String] = ["alertid", "clock", "subject", "message", "status", "sendto", "alerttype"],
        sortfield: String = "clock",
        sortorder: String = "DESC",
        limit: Int = 50
    ) {
        self.output = output
        self.time_from = sinceUnixTime
        self.sortfield = sortfield
        self.sortorder = sortorder
        self.limit = limit
        self.actionids = (actionIDs?.isEmpty == false) ? actionIDs : nil
        self.mediatypeids = (mediatypeIDs?.isEmpty == false) ? mediatypeIDs : nil
        self.userids = (userIDs?.isEmpty == false) ? userIDs : nil
        self.statuses = (statuses?.isEmpty == false) ? statuses : nil
    }

    private enum CodingKeys: String, CodingKey {
        case output, time_from, sortfield, sortorder, limit, actionids, mediatypeids, userids, filter
    }

    private struct StatusFilter: Encodable { let status: [Int] }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(output, forKey: .output)
        try container.encode(time_from, forKey: .time_from)
        try container.encode(sortfield, forKey: .sortfield)
        try container.encode(sortorder, forKey: .sortorder)
        try container.encode(limit, forKey: .limit)
        try container.encodeIfPresent(actionids, forKey: .actionids)
        try container.encodeIfPresent(mediatypeids, forKey: .mediatypeids)
        try container.encodeIfPresent(userids, forKey: .userids)
        if let statuses { try container.encode(StatusFilter(status: statuses), forKey: .filter) }
    }
}

/// Parameters for `drule.get` when listing network discovery rules.
nonisolated struct ZabbixDiscoveryRuleGetParameters: Encodable, Sendable {
    /// Discovery rule fields to return.
    let output: [String]

    /// When `true`, restricts to enabled rules (`filter: {status: 0}`) — Zabbix's Discovery status
    /// widget lists only active rules, never disabled ones.
    let activeOnly: Bool

    /// Sort rules alphabetically by name, matching the widget's own ordering.
    let sortfield: [String]
    let sortorder: String

    init(output: [String] = ["druleid", "name", "status"], activeOnly: Bool = true) {
        self.output = output
        self.activeOnly = activeOnly
        self.sortfield = ["name"]
        self.sortorder = "ASC"
    }

    private enum CodingKeys: String, CodingKey {
        case output, filter, sortfield, sortorder
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(output, forKey: .output)
        if activeOnly {
            try container.encode(ZabbixDiscoveryRuleStatusFilter(), forKey: .filter)
        }
        try container.encode(sortfield, forKey: .sortfield)
        try container.encode(sortorder, forKey: .sortorder)
    }
}

/// Restricts `drule.get` to enabled (status 0) discovery rules.
nonisolated struct ZabbixDiscoveryRuleStatusFilter: Encodable, Sendable {
    let status = 0
}

/// Parameters for `event.get` when ranking triggers by problem-event frequency over a window.
///
/// Restricts to trigger problem events (`source`/`object` 0, `value` 1) in `[time_from, time_till]`,
/// scoped by the widget's severities / host groups / tags. The events are counted per `objectid`
/// (trigger) by the caller, so the ranking is "how many times did each trigger fire", which is what
/// Zabbix's Top triggers widget shows — not the current problem list sorted by severity.
nonisolated struct ZabbixProblemEventGetParameters: Encodable, Sendable {
    let output: [String]
    let source = 0
    let object = 0
    let value = 1
    let severities: [Int]?
    let groupids: [String]?
    let time_from: Int
    let time_till: Int
    let tags: [ZabbixTagFilter]?
    let evaltype: Int?
    let sortfield: [String]
    let sortorder: String
    let limit: Int

    init(
        timeFrom: Int,
        timeTill: Int,
        severities: [Int]? = nil,
        groupIDs: [String]? = nil,
        tags: [ZabbixTagFilter]? = nil,
        evaltype: Int? = nil,
        output: [String] = ["eventid", "objectid", "severity", "name", "clock"],
        sortfield: [String] = ["clock"],
        sortorder: String = "DESC",
        limit: Int = 5000
    ) {
        self.output = output
        self.time_from = timeFrom
        self.time_till = timeTill
        self.severities = severities
        self.groupids = (groupIDs?.isEmpty == false) ? groupIDs : nil
        self.tags = (tags?.isEmpty == false) ? tags : nil
        self.evaltype = (tags?.isEmpty == false) ? evaltype : nil
        self.sortfield = sortfield
        self.sortorder = sortorder
        self.limit = limit
    }

    private enum CodingKeys: String, CodingKey {
        case output, source, object, value, severities, groupids, time_from, time_till, tags, evaltype, sortfield, sortorder, limit
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(output, forKey: .output)
        try container.encode(source, forKey: .source)
        try container.encode(object, forKey: .object)
        try container.encode(value, forKey: .value)
        try container.encodeIfPresent(severities, forKey: .severities)
        try container.encodeIfPresent(groupids, forKey: .groupids)
        try container.encode(time_from, forKey: .time_from)
        try container.encode(time_till, forKey: .time_till)
        try container.encodeIfPresent(tags, forKey: .tags)
        try container.encodeIfPresent(evaltype, forKey: .evaltype)
        try container.encode(sortfield, forKey: .sortfield)
        try container.encode(sortorder, forKey: .sortorder)
        try container.encode(limit, forKey: .limit)
    }
}

/// Parameters for `dhost.get` when counting discovered hosts per rule.
nonisolated struct ZabbixDiscoveredHostGetParameters: Encodable, Sendable {
    /// Discovery rule identifiers to fetch discovered hosts for.
    let druleids: [String]

    /// Discovered host fields to return.
    let output: [String]

    init(druleIDs: [String], output: [String] = ["dhostid", "druleid", "status"]) {
        self.druleids = druleIDs
        self.output = output
    }
}

/// Parameters for `httptest.get` when listing web monitoring scenarios.
nonisolated struct ZabbixWebScenarioGetParameters: Encodable, Sendable {
    /// Restricts to these host groups, when specified.
    let groupids: [String]?

    /// Restricts to these hosts, when specified.
    let hostids: [String]?

    /// Web scenario fields to return.
    let output: [String]

    /// Requests each scenario's host.
    let selectHosts: [String]

    /// The widget's own tag filter (from its `tags.N.*` fields); web scenarios support the same
    /// tag/operator/evaltype filtering as problems. Omitted when empty so an unfiltered query is
    /// unchanged.
    let tags: [ZabbixTagFilter]?

    /// Tag evaluation type (`evaltype`): 0 = And/Or, 2 = Or. Only sent alongside a non-empty `tags`.
    let evaltype: Int?

    init(
        groupIDs: [String]? = nil,
        hostIDs: [String]? = nil,
        tags: [ZabbixTagFilter]? = nil,
        evaltype: Int? = nil,
        output: [String] = ["httptestid", "name"],
        selectHosts: [String] = ["hostid", "name"]
    ) {
        self.groupids = groupIDs
        self.hostids = hostIDs
        self.output = output
        self.selectHosts = selectHosts
        self.tags = (tags?.isEmpty == false) ? tags : nil
        self.evaltype = (tags?.isEmpty == false) ? evaltype : nil
    }
}

/// Parameters for `item.get` when fetching the `web.test.fail[...]` internal items that back a web
/// scenario's Ok/Failed status. `webitems: true` is required — these items are created by the web
/// scenario itself and `item.get` omits them by default.
nonisolated struct ZabbixWebFailItemGetParameters: Encodable, Sendable {
    /// Restricts to these host groups, matching the widget's scope.
    let groupids: [String]?

    /// Restricts to these hosts, matching the widget's scope.
    let hostids: [String]?

    /// Item fields to return.
    let output: [String]

    /// Includes web-scenario-created items, which are excluded from `item.get` by default.
    let webitems: Bool

    /// Substring search on the item key to fetch only the fail-status items in one round trip.
    let search: [String: String]

    init(groupIDs: [String]? = nil, hostIDs: [String]? = nil) {
        self.groupids = groupIDs
        self.hostids = hostIDs
        self.output = ["itemid", "key_", "lastvalue", "hostid"]
        self.webitems = true
        self.search = ["key_": "web.test.fail["]
    }
}

/// Parameters for `host.get` when listing enabled hosts by name, as used by widgets that scope
/// their own item queries to a host list (top hosts, data overview).
nonisolated struct ZabbixHostListParameters: Encodable, Sendable {
    /// Restricts to these host groups, when specified.
    let groupids: [String]?

    /// Restricts to these hosts, when specified.
    let hostids: [String]?

    /// Host fields to return.
    let output: [String]

    /// Restricts results to enabled hosts.
    let filter: ZabbixEnabledFilter

    init(groupIDs: [String]? = nil, hostIDs: [String]? = nil, output: [String] = ["hostid", "name"]) {
        self.groupids = groupIDs
        self.hostids = hostIDs
        self.output = output
        self.filter = ZabbixEnabledFilter()
    }
}

/// Search filter for `host.get` by visible-name patterns.
nonisolated struct ZabbixHostNameSearch: Encodable, Sendable {
    let name: [String]
}

/// Status filter for `host.get` (0 = enabled/monitored, 1 = disabled).
nonisolated struct ZabbixHostStatusFilter: Encodable, Sendable {
    let status: Int
}

/// Parameters for `host.get` when a widget scopes hosts by name pattern, status, and/or host tags
/// (host navigator). Unlike `ZabbixHostListParameters`, status is not hardcoded to enabled-only.
nonisolated struct ZabbixHostScopedParameters: Encodable, Sendable {
    let groupids: [String]?
    let output: [String]
    let search: ZabbixHostNameSearch?
    let searchWildcardsEnabled: Bool?
    let searchByAny: Bool?
    let filter: ZabbixHostStatusFilter?
    let tags: [ZabbixTagFilter]?
    let evaltype: Int?

    init(groupIDs: [String]?, namePatterns: [String], status: Int?, tags: [ZabbixTagFilter]?, evalType: Int?, output: [String] = ["hostid", "name"]) {
        self.groupids = (groupIDs?.isEmpty == false) ? groupIDs : nil
        self.output = output
        let cleaned = namePatterns.filter { !$0.isEmpty }
        self.search = cleaned.isEmpty ? nil : ZabbixHostNameSearch(name: cleaned)
        self.searchWildcardsEnabled = cleaned.isEmpty ? nil : true
        self.searchByAny = cleaned.isEmpty ? nil : true
        // Widget status: -1 = Any (no filter), 0 = Enabled, 1 = Disabled.
        self.filter = (status == 0 || status == 1) ? ZabbixHostStatusFilter(status: status!) : nil
        self.tags = (tags?.isEmpty == false) ? tags : nil
        self.evaltype = (tags?.isEmpty == false) ? evalType : nil
    }

    private enum CodingKeys: String, CodingKey { case groupids, output, search, searchWildcardsEnabled, searchByAny, filter, tags, evaltype }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(groupids, forKey: .groupids)
        try container.encode(output, forKey: .output)
        try container.encodeIfPresent(search, forKey: .search)
        try container.encodeIfPresent(searchWildcardsEnabled, forKey: .searchWildcardsEnabled)
        try container.encodeIfPresent(searchByAny, forKey: .searchByAny)
        try container.encodeIfPresent(filter, forKey: .filter)
        try container.encodeIfPresent(tags, forKey: .tags)
        try container.encodeIfPresent(evaltype, forKey: .evaltype)
    }
}

/// Parameters for `host.get` when resolving hosts with geographic coordinates for the geomap widget.
nonisolated struct ZabbixHostInventoryParameters: Encodable, Sendable {
    /// Restricts to these host groups, when specified.
    let groupids: [String]?

    /// Restricts to these hosts, when specified.
    let hostids: [String]?

    /// Host fields to return.
    let output: [String]

    /// Requests each host's inventory data.
    let selectInventory: [String]

    /// Restricts results to enabled hosts.
    let filter: ZabbixEnabledFilter

    init(
        groupIDs: [String]? = nil,
        hostIDs: [String]? = nil,
        output: [String] = ["hostid", "name"],
        selectInventory: [String] = ["location_lat", "location_lon"]
    ) {
        self.groupids = groupIDs
        self.hostids = hostIDs
        self.output = output
        self.selectInventory = selectInventory
        self.filter = ZabbixEnabledFilter()
    }
}

/// Parameters for `map.get` when listing available network maps by name only.
nonisolated struct ZabbixMapListParameters: Encodable, Sendable {
    /// Map fields to return.
    let output: [String]

    init(output: [String] = ["sysmapid", "name"]) {
        self.output = output
    }
}

/// Parameters for `map.get` when fetching several maps' elements (for navtree node severity) —
/// only the element list, not the full topology the network-map widget needs.
nonisolated struct ZabbixMapElementsGetParameters: Encodable, Sendable {
    let sysmapids: [String]
    let output: [String]
    let selectSelements: String

    init(sysmapIDs: [String], output: [String] = ["sysmapid"], selectSelements: String = "extend") {
        self.sysmapids = sysmapIDs
        self.output = output
        self.selectSelements = selectSelements
    }
}

/// Parameters for `map.get` when fetching a single map's full topology.
nonisolated struct ZabbixNetworkMapGetParameters: Encodable, Sendable {
    /// Map identifier to fetch.
    let sysmapids: [String]

    /// Map fields to return.
    let output: [String]

    /// Requests full element details.
    let selectSelements: String

    /// Requests full link details.
    let selectLinks: String

    init(
        mapID: String,
        output: [String] = ["sysmapid", "name", "width", "height", "backgroundid"],
        selectSelements: String = "extend",
        selectLinks: String = "extend"
    ) {
        self.sysmapids = [mapID]
        self.output = output
        self.selectSelements = selectSelements
        self.selectLinks = selectLinks
    }
}

/// Parameters for `sla.get`.
nonisolated struct ZabbixSLAGetParameters: Encodable, Sendable {
    /// SLA identifiers to fetch, when specified.
    let slaids: [String]?

    /// SLA fields to return.
    let output: [String]

    init(slaIDs: [String]? = nil, output: [String] = ["slaid", "name", "slo"]) {
        self.slaids = slaIDs
        self.output = output
    }
}

/// Parameters for `sla.getsli`, which computes achieved SLI over recent periods for an SLA.
nonisolated struct ZabbixSLIGetParameters: Encodable, Sendable {
    /// The SLA to report on.
    let slaid: String

    /// Restricts to these services; when nil, every service attached to the SLA is reported.
    let serviceids: [String]?

    /// Number of most-recent reporting periods to return.
    let periods: Int

    init(slaID: String, serviceIDs: [String]? = nil, periods: Int = 1) {
        self.slaid = slaID
        self.serviceids = (serviceIDs?.isEmpty == false) ? serviceIDs : nil
        self.periods = periods
    }
}

/// Parameters for `hanode.get` when listing HA cluster nodes for the System information widget.
nonisolated struct ZabbixHANodeGetParameters: Encodable, Sendable {
    let output: [String]

    init(output: [String] = ["name", "status"]) {
        self.output = output
    }
}

/// Parameters for `service.get` when resolving service names by ID for SLA report labels.
nonisolated struct ZabbixServiceGetParameters: Encodable, Sendable {
    let serviceids: [String]
    let output: [String]

    init(serviceIDs: [String], output: [String] = ["serviceid", "name"]) {
        self.serviceids = serviceIDs
        self.output = output
    }
}

/// Parameters for `image.get` when fetching a single image's base64-encoded content.
nonisolated struct ZabbixImageGetParameters: Encodable, Sendable {
    /// Image identifiers to fetch.
    let imageids: [String]

    /// Requests the base64-encoded image content, not just its metadata.
    let select_image: Bool

    init(imageID: String) {
        self.imageids = [imageID]
        self.select_image = true
    }

    init(imageIDs: [String]) {
        self.imageids = imageIDs
        self.select_image = true
    }
}
