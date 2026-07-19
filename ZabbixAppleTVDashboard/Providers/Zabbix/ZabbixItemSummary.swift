//
//  ZabbixItemSummary.swift
//  ZabbixAppleTVDashboard
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

    /// The value recorded before `lastvalue`, if any — Zabbix returns this directly rather than
    /// requiring a separate history lookup, used to show an up/down trend indicator matching
    /// Zabbix's own item-value widget.
    let prevvalue: String?

    /// Unix timestamp of when `lastvalue` was recorded, shown as a "last updated" time on
    /// Zabbix's own item-value widget.
    let lastclock: String?

    /// Unit label configured on the item, e.g. "°C" or "%".
    let units: String?

    /// Zabbix value type: 0 = float, 1 = character, 2 = log, 3 = unsigned, 4 = text. Used to query
    /// the matching `history.get` table, which is keyed by value type rather than a single table.
    let value_type: ZabbixNumericString?

    /// The item's value map, when it has one configured (requested via `selectValueMap`). Lets a
    /// raw reading like "1" be shown as its human label, e.g. "Up (1)", matching Zabbix's own
    /// item-value and gauge widgets.
    let valuemap: ZabbixValueMapField?

    /// The item's host (requested via `selectHosts`), so label-macro templates can resolve
    /// "{HOST.NAME}". Optional because not every `item.get` caller selects it.
    let hosts: [ZabbixHostReference]?
}

/// Decodes Zabbix's `selectValueMap` result, which is the value map object when the item has one
/// and an empty array `[]` when it doesn't (Zabbix's convention for "no related object", the same
/// object-or-empty-array shape seen elsewhere in its API).
nonisolated struct ZabbixValueMapField: Decodable, Sendable {
    let valueMap: ZabbixValueMap?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.valueMap = (try? container.decode(ZabbixValueMap.self))
    }
}

/// A value map: an ordered set of rules turning a raw item value into a display label.
nonisolated struct ZabbixValueMap: Decodable, Sendable {
    let mappings: [ZabbixValueMapping]

    /// Resolves a raw item value to its mapped label, or `nil` if nothing maps it — mirroring how
    /// Zabbix applies a value map: the first exact/threshold/range rule that matches wins, and a
    /// "default" rule (if present) is the fallback used only when no other rule matches.
    func mappedText(for rawValue: String) -> String? {
        let numeric = Double(rawValue)
        var defaultText: String?

        for mapping in mappings {
            switch mapping.type?.intValue ?? 0 {
            case 5: // default (fallback)
                defaultText = mapping.newvalue
            case 0: // equals
                if mapping.value == rawValue { return mapping.newvalue }
                if let numeric, let mapped = Double(mapping.value), numeric == mapped { return mapping.newvalue }
            case 1: // is greater than or equals
                if let numeric, let threshold = Double(mapping.value), numeric >= threshold { return mapping.newvalue }
            case 2: // is less than or equals
                if let numeric, let threshold = Double(mapping.value), numeric <= threshold { return mapping.newvalue }
            case 3: // in range
                if let numeric, Self.value(numeric, matchesRangeSpec: mapping.value) { return mapping.newvalue }
            default:
                break // 4 = regexp, not resolved here
            }
        }
        return defaultText
    }

    /// Matches Zabbix's range syntax: a comma-separated list of `a-b` ranges (inclusive) or single
    /// numbers, e.g. "1-9,20-29". Kept deliberately simple — negative-bound ranges aren't parsed.
    private static func value(_ value: Double, matchesRangeSpec spec: String) -> Bool {
        for part in spec.split(separator: ",") {
            let bounds = part.split(separator: "-", maxSplits: 1)
            if bounds.count == 2, let low = Double(bounds[0]), let high = Double(bounds[1]) {
                if value >= low, value <= high { return true }
            } else if let single = Double(part), value == single {
                return true
            }
        }
        return false
    }
}

/// A single value-map rule. `type`: 0 = equals, 1 = ≥, 2 = ≤, 3 = in range, 4 = regexp, 5 = default.
nonisolated struct ZabbixValueMapping: Decodable, Sendable {
    let type: ZabbixNumericString?
    let value: String
    let newvalue: String
}
