//
//  ZabbixValueFormatting.swift
//  DashboardOps
//
//  Created by Codex on 7/8/26.
//

import Foundation

/// Formats numeric item values the way Zabbix's own frontend does: applying a metric-style
/// K/M/G/T suffix prepended to the item's units (e.g. "bps" -> "Mbps") once a value's magnitude
/// calls for it. A chart's whole axis picks ONE scale from its largest value rather than letting
/// each label rescale independently, so gridlines stay proportionate (e.g. "0, 200, 400 ... 1000
/// Mbps" rather than mixing Mbps and Gbps on the same axis).
enum ZabbixValueFormatting {
    struct Scale {
        let divisor: Double
        let prefix: String
    }

    private static let scales: [Scale] = [
        Scale(divisor: 1e12, prefix: "T"),
        Scale(divisor: 1e9, prefix: "G"),
        Scale(divisor: 1e6, prefix: "M"),
        Scale(divisor: 1e3, prefix: "K"),
    ]

    /// Units where a metric prefix would confuse rather than clarify (percentages, unit-less
    /// counts, raw timestamps).
    private static let unscaledUnits: Set<String> = ["%", "", "unixtime"]

    /// Chooses a single scale for a whole series/axis, based on the largest magnitude present.
    static func scale(forMaxMagnitude maxValue: Double, units: String) -> Scale {
        guard !unscaledUnits.contains(units) else { return Scale(divisor: 1, prefix: "") }

        let magnitude = abs(maxValue)
        for candidate in scales where magnitude / candidate.divisor >= 1 {
            return candidate
        }
        return Scale(divisor: 1, prefix: "")
    }

    /// Formats a value using a previously-chosen scale, appending the scaled unit suffix.
    static func format(_ value: Double, units: String, scale: Scale) -> String {
        let suffix = "\(scale.prefix)\(units)"
        let formattedNumber = formattedNumber(value / scale.divisor)
        return suffix.isEmpty ? formattedNumber : "\(formattedNumber) \(suffix)"
    }

    /// Formats a single value standalone, choosing its own best-fit scale.
    static func format(_ value: Double, units: String) -> String {
        format(value, units: units, scale: scale(forMaxMagnitude: value, units: units))
    }

    /// Formats a value the way Zabbix's own "Item value" widget does: always two decimal places
    /// (verified live — a plain integer reading like "1" is shown as "1.00", not just "1"),
    /// unlike the variable-precision `format(_:units:)` used for graph axis labels.
    static func formatItemValue(_ value: Double, units: String) -> String {
        let scale = scale(forMaxMagnitude: value, units: units)
        let suffix = "\(scale.prefix)\(units)"
        let formattedNumber = String(format: "%.2f", value / scale.divisor)
        return suffix.isEmpty ? formattedNumber : "\(formattedNumber) \(suffix)"
    }

    private static func formattedNumber(_ value: Double) -> String {
        let rounded = value.rounded()
        if abs(value - rounded) < 0.05 {
            return String(format: "%.0f", rounded)
        }
        return String(format: "%.1f", value)
    }
}
