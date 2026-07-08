//
//  DashboardWidgetContentViews.swift
//  DashboardOps
//
//  Created by Codex on 7/7/26.
//

import SwiftUI

/// Custom arc-based gauge, since SwiftUI's native `Gauge` control is unavailable on tvOS.
struct GaugeWidgetContentView: View {
    let reading: GaugeReading

    private var fraction: Double {
        let range = reading.maxValue - reading.minValue
        guard range > 0 else { return 0 }
        return ((reading.value - reading.minValue) / range).clamped(to: 0...1)
    }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .trim(from: 0, to: 0.75)
                    .stroke(DashboardTheme.secondaryCardBackground, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(135))

                Circle()
                    .trim(from: 0, to: 0.75 * fraction)
                    .stroke(gaugeTint, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(135))

                Text(reading.units.isEmpty ? formatted(reading.value) : "\(formatted(reading.value)) \(reading.units)")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(DashboardTheme.primaryText)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
            }
            .frame(maxWidth: 90, maxHeight: 90)

            Text(reading.name)
                .font(.system(size: 15, weight: .regular, design: .rounded))
                .foregroundStyle(DashboardTheme.secondaryText)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    private var gaugeTint: Color {
        let matchingThreshold = reading.thresholds.last { $0.value <= reading.value }
        guard let hex = matchingThreshold?.colorHex, let color = Color(hex: hex) else {
            return DashboardTheme.accent
        }
        return color
    }

    private func formatted(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0 ? String(format: "%.0f", value) : String(format: "%.1f", value)
    }
}

struct HoneycombWidgetContentView: View {
    let cells: [HoneycombCell]

    private let columns = [GridItem(.adaptive(minimum: 90), spacing: 6)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(cells) { cell in
                    VStack(spacing: 2) {
                        Text(cell.value)
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(DashboardTheme.primaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)

                        Text(cell.primaryLabel)
                            .font(.system(size: 12, weight: .regular, design: .rounded))
                            .foregroundStyle(DashboardTheme.secondaryText)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, minHeight: 60)
                    .background(DashboardTheme.secondaryCardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
        }
    }
}

struct TopHostsWidgetContentView: View {
    let columns: [String]
    let rows: [TopHostsRow]

    var body: some View {
        if rows.isEmpty {
            Text("No hosts match this widget's filters")
                .font(.system(size: 16, weight: .regular, design: .rounded))
                .foregroundStyle(DashboardTheme.secondaryText)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        ForEach(Array(columns.enumerated()), id: \.offset) { _, title in
                            Text(title)
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(DashboardTheme.secondaryText)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    ForEach(rows) { row in
                        HStack {
                            ForEach(Array(row.values.enumerated()), id: \.offset) { _, value in
                                Text(value)
                                    .font(.system(size: 16, weight: .medium, design: .rounded))
                                    .foregroundStyle(DashboardTheme.primaryText)
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
            }
        }
    }
}

struct TriggerOverviewWidgetContentView: View {
    let rows: [TriggerOverviewRow]

    var body: some View {
        if rows.isEmpty {
            Text("No active triggers")
                .font(.system(size: 16, weight: .regular, design: .rounded))
                .foregroundStyle(DashboardTheme.secondaryText)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(rows) { row in
                        HStack(alignment: .top, spacing: 10) {
                            Text(row.hostName)
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .foregroundStyle(DashboardTheme.secondaryText)
                                .frame(width: 110, alignment: .leading)
                                .lineLimit(1)

                            HStack(spacing: 4) {
                                ForEach(row.triggers.prefix(20)) { trigger in
                                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                                        .fill(severityIndicatorColor(for: trigger.severity))
                                        .frame(width: 14, height: 14)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

struct ProblemHostsWidgetContentView: View {
    let summaries: [HostGroupProblemSummary]

    var body: some View {
        if summaries.isEmpty {
            Text("No host groups with active problems")
                .font(.system(size: 16, weight: .regular, design: .rounded))
                .foregroundStyle(DashboardTheme.secondaryText)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(summaries.prefix(6)) { summary in
                    HStack(spacing: 10) {
                        Circle()
                            .fill(severityIndicatorColor(for: summary.maxSeverity))
                            .frame(width: 12, height: 12)

                        Text(summary.groupName)
                            .font(.system(size: 17, weight: .medium, design: .rounded))
                            .foregroundStyle(DashboardTheme.primaryText)
                            .lineLimit(1)

                        Spacer()

                        Text("\(summary.count)")
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundStyle(DashboardTheme.secondaryText)
                    }
                }
            }
        }
    }
}

struct ActionLogWidgetContentView: View {
    let entries: [ActionLogEntry]

    var body: some View {
        if entries.isEmpty {
            Text("No notifications in the last 7 days")
                .font(.system(size: 16, weight: .regular, design: .rounded))
                .foregroundStyle(DashboardTheme.secondaryText)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(entries.prefix(15)) { entry in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(entry.status == 1 ? Color.green : Color.red)
                                .frame(width: 8, height: 8)

                            VStack(alignment: .leading, spacing: 1) {
                                Text(entry.subject)
                                    .font(.system(size: 15, weight: .medium, design: .rounded))
                                    .foregroundStyle(DashboardTheme.primaryText)
                                    .lineLimit(1)
                                Text(entry.recipient)
                                    .font(.system(size: 12, weight: .regular, design: .rounded))
                                    .foregroundStyle(DashboardTheme.secondaryText)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }
        }
    }
}

struct DiscoveryStatusWidgetContentView: View {
    let rules: [DiscoveryRuleStatus]

    var body: some View {
        if rules.isEmpty {
            Text("No discovery rules configured")
                .font(.system(size: 16, weight: .regular, design: .rounded))
                .foregroundStyle(DashboardTheme.secondaryText)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(rules.prefix(6)) { rule in
                    HStack(spacing: 10) {
                        Circle()
                            .fill(rule.isEnabled ? Color.green : Color.gray)
                            .frame(width: 10, height: 10)

                        Text(rule.name)
                            .font(.system(size: 16, weight: .medium, design: .rounded))
                            .foregroundStyle(DashboardTheme.primaryText)
                            .lineLimit(1)

                        Spacer()

                        Text("\(rule.upCount) up")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(.green)

                        if rule.downCount > 0 {
                            Text("\(rule.downCount) down")
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
        }
    }
}

struct WebMonitoringWidgetContentView: View {
    let scenarios: [WebScenarioSummary]

    var body: some View {
        if scenarios.isEmpty {
            Text("No web scenarios configured")
                .font(.system(size: 16, weight: .regular, design: .rounded))
                .foregroundStyle(DashboardTheme.secondaryText)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(scenarios.prefix(15)) { scenario in
                        HStack(spacing: 8) {
                            Text(scenario.name)
                                .font(.system(size: 16, weight: .medium, design: .rounded))
                                .foregroundStyle(DashboardTheme.primaryText)
                                .lineLimit(1)

                            if let host = scenario.hostName {
                                Text(host)
                                    .font(.system(size: 13, weight: .regular, design: .rounded))
                                    .foregroundStyle(DashboardTheme.secondaryText)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }
        }
    }
}

struct ItemHistoryWidgetContentView: View {
    let series: [ItemHistorySeries]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(series) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.itemName)
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(DashboardTheme.secondaryText)
                            .lineLimit(1)

                        ForEach(item.values.prefix(3)) { point in
                            HStack {
                                Text(item.units.isEmpty ? point.value : "\(point.value) \(item.units)")
                                    .font(.system(size: 17, weight: .medium, design: .rounded))
                                    .foregroundStyle(DashboardTheme.primaryText)
                                Spacer()
                                Text(point.date, style: .time)
                                    .font(.system(size: 13, weight: .regular, design: .rounded))
                                    .foregroundStyle(DashboardTheme.secondaryText)
                            }
                        }
                    }
                }
            }
        }
    }
}

struct DataOverviewWidgetContentView: View {
    let entries: [DataOverviewEntry]

    var body: some View {
        if entries.isEmpty {
            Text("No items match this widget's filters")
                .font(.system(size: 16, weight: .regular, design: .rounded))
                .foregroundStyle(DashboardTheme.secondaryText)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(entries.prefix(30)) { entry in
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(entry.itemName)
                                    .font(.system(size: 15, weight: .medium, design: .rounded))
                                    .foregroundStyle(DashboardTheme.primaryText)
                                    .lineLimit(1)
                                Text(entry.hostName)
                                    .font(.system(size: 12, weight: .regular, design: .rounded))
                                    .foregroundStyle(DashboardTheme.secondaryText)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Text(entry.units.isEmpty ? entry.value : "\(entry.value) \(entry.units)")
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .foregroundStyle(DashboardTheme.accent)
                        }
                    }
                }
            }
        }
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

private extension Color {
    /// Creates a color from a "RRGGBB" hex string, as used by Zabbix widget threshold fields.
    init?(hex: String) {
        var sanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if sanitized.hasPrefix("#") {
            sanitized.removeFirst()
        }

        guard sanitized.count == 6, let value = UInt32(sanitized, radix: 16) else {
            return nil
        }

        let red = Double((value >> 16) & 0xFF) / 255
        let green = Double((value >> 8) & 0xFF) / 255
        let blue = Double(value & 0xFF) / 255
        self = Color(red: red, green: green, blue: blue)
    }
}
