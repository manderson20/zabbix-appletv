//
//  ZabbixValueFormatting.swift
//  ZabbixAppleTVDashboard
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

    private static let prefixesLargestFirst: [(power: Double, prefix: String)] = [
        (4, "T"), (3, "G"), (2, "M"), (1, "K"),
    ]

    /// Units where a metric prefix would confuse rather than clarify (percentages, unit-less
    /// counts, raw timestamps).
    private static let unscaledUnits: Set<String> = ["%", "", "unixtime"]

    /// The step between K/M/G/T for a unit. Zabbix scales the byte family — exactly the units "B"
    /// and "Bps" — by 1024 (binary prefixes: 16106127360 B → "15 GB"), and everything else (bps
    /// included) by 1000. Using 1000 for bytes inflated every memory/disk label ~7.4% versus the
    /// frontend (16.68 GB where Zabbix shows 15.53 GB for the same reading) — verified against
    /// live values whose ratio was exactly 1024³/1000³.
    private static func base(forUnits units: String) -> Double {
        units == "B" || units == "Bps" ? 1024 : 1000
    }

    /// Chooses a single scale for a whole series/axis, based on the largest magnitude present.
    static func scale(forMaxMagnitude maxValue: Double, units: String) -> Scale {
        guard !unscaledUnits.contains(units) else { return Scale(divisor: 1, prefix: "") }

        let base = base(forUnits: units)
        let magnitude = abs(maxValue)
        for candidate in prefixesLargestFirst {
            let divisor = pow(base, candidate.power)
            if magnitude / divisor >= 1 {
                return Scale(divisor: divisor, prefix: candidate.prefix)
            }
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

    /// Formats a value the way Zabbix's own "Item value" widget does: a fixed number of decimal
    /// places (its `decimal_places`, default 2 — a plain integer reading like "1" is shown as
    /// "1.00"), unlike the variable-precision `format(_:units:)` used for graph axis labels. Pass
    /// `units: ""` to suppress the unit suffix (the widget's `units_show` = off).
    static func formatItemValue(_ value: Double, units: String, decimalPlaces: Int = 2) -> String {
        let scale = scale(forMaxMagnitude: value, units: units)
        let suffix = "\(scale.prefix)\(units)"
        let clampedDecimals = max(0, min(decimalPlaces, 10))
        let formattedNumber = String(format: "%.\(clampedDecimals)f", value / scale.divisor)
        return suffix.isEmpty ? formattedNumber : "\(formattedNumber) \(suffix)"
    }

    private static func formattedNumber(_ value: Double) -> String {
        let rounded = value.rounded()
        if abs(value - rounded) < 0.05 {
            return String(format: "%.0f", rounded)
        }
        return String(format: "%.1f", value)
    }

    /// Formats a graph-legend statistic the way Zabbix's classic-graph legend does: roughly four
    /// significant digits with trailing noise dropped ("0.07917 %", "14.07 GB", "1.9836 %"), rather
    /// than the axis labels' coarser 0–1 decimal rounding that collapses small readings to "0 %".
    static func formatLegendStat(_ value: Double, units: String) -> String {
        let scale = scale(forMaxMagnitude: value, units: units)
        let suffix = "\(scale.prefix)\(units)"
        let formattedNumber = String(format: "%.4g", value / scale.divisor)
        return suffix.isEmpty ? formattedNumber : "\(formattedNumber) \(suffix)"
    }
}
