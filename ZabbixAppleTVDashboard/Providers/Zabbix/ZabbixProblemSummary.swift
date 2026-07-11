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

    /// Unix timestamp the problem started, as a string per Zabbix API convention.
    let clock: String

    /// Identifier of the underlying trigger, used to resolve the host via `trigger.get`.
    let objectid: String
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
