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

/// A single hourly trend record, as returned by `trend.get`. Trends are kept far longer than raw
/// history, so they're used to fill the part of a long graph window that history no longer covers.
nonisolated struct ZabbixTrendValue: Decodable, Sendable {
    /// Unix timestamp of the start of the trend's hour, as a string per Zabbix API convention.
    let clock: String

    /// Average value over the hour. The default drawn for the trend-covered part of a graph,
    /// matching Zabbix's own default approximation.
    let value_avg: String

    /// Minimum / maximum over the hour, requested and used when a dataset's `approximation` selects
    /// min or max rather than the average. Optional because a caller may request only `value_avg`.
    let value_min: String?
    let value_max: String?
}
