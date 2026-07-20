//
//  GraphAxisMath.swift
//  ZabbixAppleTVDashboard
//
//  Created by Claude on 7/19/26.
//

import Foundation

/// Axis-grid math for the chart widgets, mirroring how Zabbix lays out its graphs: the Y axis
/// snaps to "nice" grid steps (1/2/5 × 10ⁿ in *displayed* units) and labels every step with
/// exactly the decimals the step size calls for — a 0.005 GB step reads "14.095 GB", never a
/// repeated "14.1 GB" — and an auto-scaled axis rounds outward to whole steps.
nonisolated enum GraphAxisMath {
    struct YAxis: Equatable {
        /// Axis bounds in raw (unscaled) units.
        let lower: Double
        let upper: Double
        /// Gridline/label positions in raw units, ascending, bounds included.
        let ticks: [Double]
        /// Fractional digits each label needs in displayed (scaled) units.
        let decimals: Int
    }

    /// The smallest "nice" step (1, 2, or 5 times a power of ten) that is at least `raw`.
    static func niceStep(atLeast raw: Double) -> Double {
        guard raw > 0, raw.isFinite else { return 1 }
        let power = pow(10, floor(log10(raw)))
        for multiple in [1.0, 2.0, 5.0, 10.0] {
            let step = multiple * power
            if step >= raw * (1 - 1e-9) { return step }
        }
        return 10 * power
    }

    /// Builds the Y-axis grid for a value range. `scaleDivisor` is the K/M/G/T divisor the labels
    /// will be displayed with — the grid is computed in displayed units so steps land on clean
    /// numbers there. Fixed bounds (an explicitly configured min/max) are kept exact with ticks
    /// placed inside them; auto bounds round outward to whole steps like Zabbix's own graphs.
    static func yAxis(
        lower: Double,
        upper: Double,
        fixedBounds: Bool,
        targetIntervals: Int,
        scaleDivisor: Double
    ) -> YAxis {
        let divisor = scaleDivisor > 0 ? scaleDivisor : 1
        var scaledLower = lower / divisor
        var scaledUpper = upper / divisor
        if scaledUpper <= scaledLower {
            scaledUpper = scaledLower + 1
        }

        let intervals = max(1, targetIntervals)
        let step = niceStep(atLeast: (scaledUpper - scaledLower) / Double(intervals))

        let firstTick: Double
        if fixedBounds {
            firstTick = (scaledLower / step).rounded(.up) * step
        } else {
            scaledLower = (scaledLower / step).rounded(.down) * step
            scaledUpper = (scaledUpper / step).rounded(.up) * step
            firstTick = scaledLower
        }

        var ticks: [Double] = []
        var tick = firstTick
        while tick <= scaledUpper + step * 1e-6 {
            ticks.append(tick * divisor)
            tick += step
        }

        let decimals = step < 1 ? Int(ceil(-log10(step) - 1e-9)) : 0
        return YAxis(lower: scaledLower * divisor, upper: scaledUpper * divisor, ticks: ticks, decimals: decimals)
    }

    /// Time-step candidates for the svggraph X axis, in seconds: whole minutes/hours/days the way
    /// Zabbix subdivides its time axis.
    private static let timeSteps: [TimeInterval] = [
        60, 120, 300, 600, 900, 1800, 3600, 7200, 10800, 21600, 43200, 86400, 172_800, 604_800,
    ]

    /// The smallest nice time step whose labels keep at least `minimumSpacing` points between
    /// them across `plotWidth`. Rotated svggraph labels need only ~15pt of horizontal room, which
    /// is how the frontend fits a label every 2 minutes on an hour-wide graph.
    static func svgTimeStep(windowSeconds: TimeInterval, plotWidth: Double, minimumSpacing: Double = 18) -> TimeInterval {
        guard windowSeconds > 0, plotWidth > 0 else { return timeSteps[0] }
        for step in timeSteps {
            if plotWidth * step / windowSeconds >= minimumSpacing { return step }
        }
        return timeSteps[timeSteps.count - 1]
    }

    /// Tick dates for the svggraph X axis: every multiple of `step` (aligned to the epoch, so an
    /// hour window ticks at :02, :04, ... like the frontend) strictly inside the window.
    static func svgTimeTicks(start: Date, end: Date, step: TimeInterval) -> [Date] {
        guard step > 0, end > start else { return [] }
        var ticks: [Date] = []
        var t = (start.timeIntervalSince1970 / step).rounded(.up) * step
        // A tick flush against either boundary would collide with the red boundary labels.
        while t < end.timeIntervalSince1970 - step * 0.25 {
            if t > start.timeIntervalSince1970 + step * 0.25 {
                ticks.append(Date(timeIntervalSince1970: t))
            }
            t += step
        }
        return ticks
    }

    /// Tick dates for the classic graph's X axis: the window divided into `intervals` equal cells
    /// (Zabbix's image graphs use an even pixel grid, not calendar-aligned steps), labeling each
    /// boundary except the window edges.
    static func classicTimeTicks(start: Date, end: Date, intervals: Int) -> [Date] {
        guard intervals > 1 else { return [] }
        let span = end.timeIntervalSince(start)
        return (1..<intervals).map { start.addingTimeInterval(span * Double($0) / Double(intervals)) }
    }
}
