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

    /// Y-axis minimum mode: 0 = calculated from data, 1 = fixed at `yaxismin`, 2 = tied to an item.
    let ymin_type: ZabbixNumericString?

    /// Y-axis maximum mode: 0 = calculated from data, 1 = fixed at `yaxismax`, 2 = tied to an item.
    let ymax_type: ZabbixNumericString?

    /// Fixed Y-axis minimum, meaningful when `ymin_type` is 1. A float string (e.g. "0.0000"), so
    /// it's kept as a string and parsed with `Double` (`ZabbixNumericString` is integer-only).
    let yaxismin: String?

    /// Fixed Y-axis maximum, meaningful when `ymax_type` is 1. Float string, as `yaxismin`.
    let yaxismax: String?

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
