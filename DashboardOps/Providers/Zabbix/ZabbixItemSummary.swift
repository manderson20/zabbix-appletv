//
//  ZabbixItemSummary.swift
//  DashboardOps
//
//  Created by Codex on 7/7/26.
//

import Foundation

/// Item metadata and last value, as returned by `item.get`.
nonisolated struct ZabbixItemSummary: Decodable, Sendable {
    /// Zabbix item identifier.
    let itemid: String

    /// Item display name.
    let name: String

    /// Most recent recorded value, if any.
    let lastvalue: String?

    /// Unit label configured on the item, e.g. "°C" or "%".
    let units: String?

    /// Zabbix value type: 0 = float, 1 = character, 2 = log, 3 = unsigned, 4 = text. Used to query
    /// the matching `history.get` table, which is keyed by value type rather than a single table.
    let value_type: ZabbixNumericString?
}
