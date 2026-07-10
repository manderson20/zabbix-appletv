//
//  DashboardWidgetGridView.swift
//  DashboardOps
//
//  Created by Codex on 7/7/26.
//

import SwiftUI

/// Lays out resolved dashboard widgets in their relative grid positions.
///
/// The number of grid columns/rows is derived from the widgets themselves (the furthest extent
/// any widget reaches) rather than a hardcoded constant, since Zabbix's dashboard grid size has
/// varied across versions.
struct DashboardWidgetGridView: View {
    /// Widgets to lay out.
    let widgets: [RenderableDashboardWidget]

    /// Computes the grid's column and row count as the furthest extent any widget reaches.
    static func gridExtent(for widgets: [RenderableDashboardWidget]) -> (columns: Int, rows: Int) {
        let columns = max(widgets.map { $0.frame.x + $0.frame.width }.max() ?? 1, 1)
        let rows = max(widgets.map { $0.frame.y + $0.frame.height }.max() ?? 1, 1)
        return (columns, rows)
    }

    var body: some View {
        let (columnCount, rowCount) = Self.gridExtent(for: widgets)

        GeometryReader { geometry in
            let columnWidth = geometry.size.width / CGFloat(columnCount)
            let rowHeight = geometry.size.height / CGFloat(rowCount)

            ZStack(alignment: .topLeading) {
                ForEach(widgets) { widget in
                    DashboardWidgetCardView(widget: widget)
                        .frame(
                            width: columnWidth * CGFloat(widget.frame.width),
                            height: rowHeight * CGFloat(widget.frame.height),
                            alignment: .top
                        )
                        .offset(
                            x: columnWidth * CGFloat(widget.frame.x),
                            y: rowHeight * CGFloat(widget.frame.y)
                        )
                }
            }
        }
    }
}

/// A single dashboard widget rendered natively.
private struct DashboardWidgetCardView: View {
    let widget: RenderableDashboardWidget

    /// Zabbix's own per-widget background color, when the widget type supports one (currently
    /// just "item value" widgets, via their "bg_color" field).
    private var backgroundColorHex: String? {
        if case let .itemValue(_, _, _, backgroundColorHex) = widget.kind {
            return backgroundColorHex
        }
        return nil
    }

    var body: some View {
        DashboardCard(backgroundColor: backgroundColorHex.flatMap(Color.init(hex:))) {
            VStack(alignment: .leading, spacing: 10) {
                if !widget.hasHiddenHeader {
                    Text(widget.title)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(DashboardTheme.primaryText)
                        .lineLimit(1)
                }

                content
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(6)
    }

    @ViewBuilder
    private var content: some View {
        switch widget.kind {
        case .clock:
            ClockWidgetContentView()
        case let .itemValue(name, value, units, _):
            ItemValueWidgetContentView(name: name, value: value, units: units)
        case let .problems(problems):
            ProblemsWidgetContentView(problems: problems)
        case let .problemsBySeverity(counts):
            ProblemsBySeverityWidgetContentView(counts: counts)
        case let .hostAvailability(breakdown):
            HostAvailabilityWidgetContentView(breakdown: breakdown)
        case let .systemInformation(serverVersion, isRunning):
            SystemInformationWidgetContentView(serverVersion: serverVersion, isRunning: isRunning)
        case let .gauge(reading):
            GaugeWidgetContentView(reading: reading)
        case let .honeycomb(cells):
            HoneycombWidgetContentView(cells: cells)
        case let .topHosts(columns, rows):
            TopHostsWidgetContentView(columns: columns, rows: rows)
        case let .topTriggers(problems):
            ProblemsWidgetContentView(problems: problems)
        case let .triggerOverview(rows):
            TriggerOverviewWidgetContentView(rows: rows)
        case let .problemsByHostGroup(summaries):
            ProblemHostsWidgetContentView(summaries: summaries)
        case let .actionLog(entries):
            ActionLogWidgetContentView(entries: entries)
        case let .discoveryStatus(rules):
            DiscoveryStatusWidgetContentView(rules: rules)
        case let .webMonitoring(scenarios):
            WebMonitoringWidgetContentView(scenarios: scenarios)
        case let .itemHistory(series):
            ItemHistoryWidgetContentView(series: series)
        case let .dataOverview(entries):
            DataOverviewWidgetContentView(entries: entries)
        case let .lineChart(series):
            LineChartWidgetContentView(series: series)
        case let .pieChart(slices):
            PieChartWidgetContentView(slices: slices)
        case let .geomap(markers):
            GeomapWidgetContentView(markers: markers)
        case let .networkMap(diagram):
            NetworkMapWidgetContentView(diagram: diagram)
        case let .mapList(maps):
            MapListWidgetContentView(maps: maps)
        case let .hostList(hosts):
            HostListWidgetContentView(hosts: hosts)
        case let .itemList(items):
            ItemListWidgetContentView(items: items)
        case let .slaReport(entries):
            SLAReportWidgetContentView(entries: entries)
        case let .unsupported(rawType):
            Text("The \"\(rawType)\" widget isn't supported yet.")
                .font(.system(size: 18, weight: .regular, design: .rounded))
                .foregroundStyle(DashboardTheme.secondaryText)
        }
    }
}

private struct ClockWidgetContentView: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Text(context.date, style: .time)
                .font(.system(size: 40, weight: .semibold, design: .rounded))
                .foregroundStyle(DashboardTheme.primaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

private struct ItemValueWidgetContentView: View {
    let name: String
    let value: String
    let units: String

    private var displayValue: String {
        guard let numericValue = Double(value) else {
            return units.isEmpty ? value : "\(value) \(units)"
        }
        return ZabbixValueFormatting.format(numericValue, units: units)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(displayValue)
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .foregroundStyle(DashboardTheme.accent)
                .lineLimit(1)
                .minimumScaleFactor(0.5)

            Text(name)
                .font(.system(size: 18, weight: .regular, design: .rounded))
                .foregroundStyle(DashboardTheme.secondaryText)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

private struct ProblemsWidgetContentView: View {
    let problems: [DashboardProblem]

    var body: some View {
        if problems.isEmpty {
            Text("No active problems")
                .font(.system(size: 18, weight: .regular, design: .rounded))
                .foregroundStyle(DashboardTheme.secondaryText)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(problems.prefix(6)) { problem in
                    HStack(alignment: .top, spacing: 10) {
                        Circle()
                            .fill(severityIndicatorColor(for: problem.severity))
                            .frame(width: 14, height: 14)
                            .padding(.top, 4)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(problem.name)
                                .font(.system(size: 18, weight: .semibold, design: .rounded))
                                .foregroundStyle(DashboardTheme.primaryText)
                                .lineLimit(1)

                            if let host = problem.host {
                                Text(host)
                                    .font(.system(size: 15, weight: .regular, design: .rounded))
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

/// Large, full-height colored blocks per severity with the count centered, matching Zabbix's own
/// "Problems by severity" widget (rather than small numbers over a thin capsule bar).
private struct ProblemsBySeverityWidgetContentView: View {
    let counts: [SeverityCount]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(counts) { count in
                VStack(spacing: 4) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(severityIndicatorColor(for: count.severity))

                        Text("\(count.count)")
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    Text(SeverityPalette.name(for: count.severity))
                        .font(.system(size: 11, weight: .regular, design: .rounded))
                        .foregroundStyle(DashboardTheme.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
            }
        }
    }
}

/// A table with column headers (Available/Not available/Mixed/Unknown/Total) and one row per
/// interface type plus a combined "Total hosts" row, matching Zabbix's own host availability
/// widget layout.
private struct HostAvailabilityWidgetContentView: View {
    let breakdown: [HostInterfaceAvailability]

    private static let nameColumnWidth: CGFloat = 130

    private struct Column {
        let title: String
        let color: Color
        let keyPath: KeyPath<HostInterfaceAvailability, Int>
    }

    private static let columns: [Column] = [
        Column(title: "Available", color: .green, keyPath: \.available),
        Column(title: "Not available", color: .red, keyPath: \.unavailable),
        Column(title: "Mixed", color: .orange, keyPath: \.mixed),
        Column(title: "Unknown", color: .gray, keyPath: \.unknown),
    ]

    var body: some View {
        // Deliberately compact: this is an unattended kiosk display, so a scrollable table isn't
        // an option the way it would be on an interactive screen — everything has to fit within
        // whatever grid height the dashboard's own layout allotted the widget.
        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 3) {
            GridRow {
                Text("")
                    .frame(width: Self.nameColumnWidth, alignment: .leading)
                ForEach(Self.columns, id: \.title) { column in
                    Text(column.title)
                        .foregroundStyle(column.color)
                }
                Text("Total")
                    .foregroundStyle(DashboardTheme.secondaryText)
            }
            .font(.system(size: 11, weight: .semibold, design: .rounded))

            ForEach(breakdown) { row in
                GridRow {
                    Text(row.interfaceTypeName)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(DashboardTheme.secondaryText)
                        .frame(width: Self.nameColumnWidth, alignment: .leading)
                        .lineLimit(1)

                    ForEach(Self.columns, id: \.title) { column in
                        Text("\(row[keyPath: column.keyPath])")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(DashboardTheme.primaryText)
                    }

                    Text("\(row.total)")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(DashboardTheme.primaryText)
                }
            }
        }
    }
}

private struct SystemInformationWidgetContentView: View {
    let serverVersion: String
    let isRunning: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            statusRow(label: "Zabbix server is running", value: isRunning ? "Yes" : "No", color: isRunning ? .green : .red)
            statusRow(label: "Zabbix server version", value: serverVersion, color: DashboardTheme.secondaryText)
        }
    }

    private func statusRow(label: String, value: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Text("\(label):")
                .font(.system(size: 16, weight: .regular, design: .rounded))
                .foregroundStyle(DashboardTheme.secondaryText)

            Text(value)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(color)
        }
    }
}

/// Maps a Zabbix problem severity (0 = not classified, 5 = disaster) to this server's own
/// configured indicator color (see `SeverityPalette`), rather than a fixed guess.
@MainActor
func severityIndicatorColor(for severity: Int) -> Color {
    SeverityPalette.color(for: severity)
}
