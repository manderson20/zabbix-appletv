//
//  ZabbixAPIParameters.swift
//  DashboardOps
//
//  Created by Codex on 7/7/26.
//

import Foundation

/// Empty object parameters for Zabbix methods that accept no object fields.
nonisolated struct ZabbixEmptyObjectParameters: Encodable, Sendable {}

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

    init(itemIDs: [String], output: [String] = ["itemid", "name", "lastvalue", "units"]) {
        self.itemids = itemIDs
        self.output = output
    }
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

    /// Field to sort results by.
    let sortfield: [String]

    /// Sort order for `sortfield`.
    let sortorder: String

    /// Maximum number of problems to return.
    let limit: Int

    init(
        output: [String] = ["eventid", "name", "severity", "clock", "objectid"],
        severities: [Int]? = nil,
        sortfield: [String] = ["eventid"],
        sortorder: String = "DESC",
        limit: Int = 20
    ) {
        self.output = output
        self.severities = severities
        self.sortfield = sortfield
        self.sortorder = sortorder
        self.limit = limit
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

    /// Restricts results to enabled hosts.
    let filter: ZabbixEnabledFilter

    init(output: [String] = ["hostid"], selectInterfaces: [String] = ["type", "available"]) {
        self.output = output
        self.selectInterfaces = selectInterfaces
        self.filter = ZabbixEnabledFilter()
    }
}

/// Parameters for a `host.get` call that returns only a count of enabled hosts.
nonisolated struct ZabbixHostCountParameters: Encodable, Sendable {
    let countOutput = true
    let filter = ZabbixEnabledFilter()
}

/// Parameters for an `item.get` call that returns only a count of enabled items.
nonisolated struct ZabbixItemCountParameters: Encodable, Sendable {
    let countOutput = true
    let filter = ZabbixEnabledFilter()
}

/// Parameters for a `problem.get` call that returns only a count of active problems.
nonisolated struct ZabbixProblemCountParameters: Encodable, Sendable {
    let countOutput = true
}
