//
//  ZabbixGraphDefinition.swift
//  ZabbixAppleTVDashboard
//
//  Created by Codex on 7/7/26.
//

import Foundation

/// A classic Graph object's member items, as returned by `graph.get` with `selectGraphItems`.
///
/// The response key is `gitems` (verified against a live Zabbix 7.0 server), not `graphitems`.
nonisolated struct ZabbixGraphDefinition: Decodable, Sendable {
    /// Zabbix graph identifier.
    let graphid: String

    /// Graph display name.
    let name: String

    /// Graph type: 0 = normal (lines), 1 = stacked, 2 = pie, 3 = exploded pie. Absent → normal.
    let graphtype: ZabbixNumericString?

    /// Member items making up this graph.
    let gitems: [ZabbixGraphItem]
}

/// A single item within a classic graph, with its configured line color.
nonisolated struct ZabbixGraphItem: Decodable, Sendable {
    /// Zabbix item identifier.
    let itemid: String

    /// Line color as a "RRGGBB" hex string.
    let color: String
}
