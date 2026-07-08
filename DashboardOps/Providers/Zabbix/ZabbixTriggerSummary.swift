//
//  ZabbixTriggerSummary.swift
//  DashboardOps
//
//  Created by Codex on 7/7/26.
//

import Foundation

/// A trigger with its host, as returned by `trigger.get` with `selectHosts`.
nonisolated struct ZabbixTriggerSummary: Decodable, Sendable {
    /// Zabbix trigger identifier.
    let triggerid: String

    /// Trigger description (its display name).
    let description: String

    /// Severity, from 0 (not classified) to 5 (disaster).
    let priority: ZabbixNumericString

    /// Hosts the trigger is defined on.
    let hosts: [ZabbixHostReference]
}
