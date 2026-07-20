//
//  ZabbixTriggerSummary.swift
//  ZabbixAppleTVDashboard
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

    /// Current trigger state: 0 = OK, 1 = PROBLEM. Present only when requested in `output`; when the
    /// query already restricts to PROBLEM-state triggers this is left unrequested and defaults to
    /// PROBLEM at the call site.
    let value: ZabbixNumericString?

    /// Hosts the trigger is defined on.
    let hosts: [ZabbixHostReference]

    /// Triggers this trigger depends on (requested via `selectDependencies`) — a non-empty list
    /// gets Zabbix's dependency arrow icon in the trigger overview cell.
    let dependencies: [ZabbixTriggerDependencyReference]?
}

/// A dependency reference returned by `trigger.get` `selectDependencies`.
nonisolated struct ZabbixTriggerDependencyReference: Decodable, Sendable {
    let triggerid: String
}

/// A trigger definition with its (expanded) expression, as fetched for a classic graph's trigger
/// threshold lines.
nonisolated struct ZabbixTriggerDefinition: Decodable, Sendable {
    /// Zabbix trigger identifier.
    let triggerid: String

    /// Trigger display name.
    let description: String

    /// Severity, from 0 (not classified) to 5 (disaster) — colors the drawn line.
    let priority: ZabbixNumericString

    /// The trigger expression with macros expanded (requested via `expandExpression`).
    let expression: String?
}
