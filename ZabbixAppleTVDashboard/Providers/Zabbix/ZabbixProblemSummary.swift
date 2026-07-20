//
//  ZabbixProblemSummary.swift
//  ZabbixAppleTVDashboard
//
//  Created by Codex on 7/7/26.
//

import Foundation

/// An active problem, as returned by `problem.get`.
///
/// `problem.get` does not support `selectHosts` (unlike most other Zabbix API methods, verified
/// against a live Zabbix 7.0 server); the host is resolved separately via `trigger.get` using
/// `objectid` as the trigger identifier.
nonisolated struct ZabbixProblemSummary: Decodable, Sendable {
    /// Zabbix event identifier.
    let eventid: String

    /// Problem name.
    let name: String

    /// Severity, from 0 (not classified) to 5 (disaster).
    let severity: ZabbixNumericString

    /// The cause event this problem is a symptom of ("0" or absent for a cause problem).
    /// Zabbix's widgets count and list only CAUSE problems at the top level — symptoms nest
    /// under their cause — so counting symptoms too inflated every tally (verified live: the
    /// Monitor Wall totals read ~300 high until symptoms were filtered).
    let cause_eventid: String?

    /// True when this problem is a top-level cause (not a symptom of another event).
    var isCause: Bool { cause_eventid == nil || cause_eventid == "0" }

    /// Unix timestamp the problem started, as a string per Zabbix API convention.
    let clock: String

    /// Identifier of the underlying trigger, used to resolve the host via `trigger.get`.
    let objectid: String

    /// Event tags (requested via `selectTags`), shown on the problems widget per its `show_tags`.
    let tags: [ZabbixEventTag]?
}

/// A single event tag (name + value), as returned by `problem.get` with `selectTags`.
nonisolated struct ZabbixEventTag: Decodable, Sendable {
    let tag: String
    let value: String
}

/// A trigger's associated hosts, as returned by `trigger.get` with `selectHosts`.
nonisolated struct ZabbixTriggerHosts: Decodable, Sendable {
    /// Zabbix trigger identifier.
    let triggerid: String

    /// Hosts the trigger is defined on.
    let hosts: [ZabbixHostReference]
}

/// A minimal host reference embedded in related object responses.
///
/// `hostid` is included even when not explicitly requested in `selectHosts` — verified against a
/// live Zabbix 7.0 server, consistent with Zabbix always returning an object's primary key.
nonisolated struct ZabbixHostReference: Decodable, Sendable {
    /// Zabbix host identifier.
    let hostid: String

    /// Host display name.
    let name: String
}
