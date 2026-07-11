//
//  ZabbixItemWithHost.swift
//  ZabbixAppleTVDashboard
//
//  Created by Codex on 7/7/26.
//

import Foundation

/// An item with its owning host, as returned by `item.get` with `selectHosts`.
///
/// Used by widgets that key item values by host (top hosts, honeycomb, data overview).
nonisolated struct ZabbixItemWithHost: Decodable, Sendable {
    /// Zabbix item identifier.
    let itemid: String

    /// Item display name.
    let name: String

    /// Most recent recorded value, if any.
    let lastvalue: String?

    /// Unit label configured on the item.
    let units: String?

    /// Zabbix value type: 0 = float, 1 = character, 2 = log, 3 = unsigned, 4 = text.
    let value_type: ZabbixNumericString?

    /// Hosts the item belongs to (an item belongs to exactly one host).
    let hosts: [ZabbixHostReference]
}
