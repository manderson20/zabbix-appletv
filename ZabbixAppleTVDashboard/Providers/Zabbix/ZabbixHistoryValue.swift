//
//  ZabbixHistoryValue.swift
//  ZabbixAppleTVDashboard
//
//  Created by Codex on 7/7/26.
//

import Foundation

/// A single historical value, as returned by `history.get`.
nonisolated struct ZabbixHistoryValue: Decodable, Sendable {
    /// Zabbix item identifier this value belongs to.
    let itemid: String

    /// Unix timestamp the value was recorded, as a string per Zabbix API convention.
    let clock: String

    /// Recorded value. Numeric, text, or log types are all represented as strings.
    let value: String
}
