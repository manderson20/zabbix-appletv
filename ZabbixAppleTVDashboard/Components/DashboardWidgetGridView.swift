//
//  DashboardWidgetGridView.swift
//  ZabbixAppleTVDashboard
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

    /// Below this, a widget stops being legible — a graph needs room for its title, axes, and
    /// legend. Some Zabbix dashboard pages configure far more total grid rows than fit in one
    /// screen (verified live: one page stacks 13 full-width graphs across 63 rows), and dividing
    /// the screen height by the row count for a page like that shrinks every widget to a few
    /// points tall with everything overlapping. Rather than keep shrinking past this floor, the
    /// page's content grows taller than the screen and auto-scrolls instead (see below).
    private static let minimumRowHeight: CGFloat = 60

    /// How fast an overflowing page scrolls, in points per second — an unattended kiosk display
    /// has no remote to scroll manually, so this is the only way every widget on a page like that
    /// actually gets seen during its time on screen rather than just the first screenful.
    private static let autoScrollPointsPerSecond: CGFloat = 40

    @State private var scrollOffset: CGFloat = 0

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
            let naturalRowHeight = geometry.size.height / CGFloat(rowCount)
            let rowHeight = max(naturalRowHeight, Self.minimumRowHeight)
            let contentHeight = rowHeight * CGFloat(rowCount)
            let overflow = (contentHeight - geometry.size.height).rounded()

            ZStack(alignment: .topLeading) {
                ForEach(widgets) { widget in
                    DashboardWidgetCardView(widget: widget)
                        .frame(
                            width: columnWidth * CGFloat(widget.frame.width),
                            height: rowHeight * CGFloat(widget.frame.height),
                            alignment: .top
                        )
                        // Each card is clipped to its own cell — a widget whose content (e.g. a
                        // long Problems list) is taller than its allotted row height should have
                        // that overflow cut off at its own bottom edge, not bleed into whatever
                        // widget happens to sit below it in the grid.
                        .clipped()
                        .offset(
                            x: columnWidth * CGFloat(widget.frame.x),
                            y: rowHeight * CGFloat(widget.frame.y) - scrollOffset
                        )
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
            .clipped()
            .task(id: overflow) {
                guard overflow > 0 else { return }

                // A short pause so the first widgets are readable before scrolling starts, then a
                // slow, steady scroll to the bottom, where it holds until the page itself rotates.
                try? await Task.sleep(nanoseconds: 3 * 1_000_000_000)
                guard !Task.isCancelled else { return }

                withAnimation(.linear(duration: Double(overflow / Self.autoScrollPointsPerSecond))) {
                    scrollOffset = overflow
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
        if case let .itemValue(_, _, _, _, backgroundColorHex, _, _, _) = widget.kind {
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
        .padding(4)
    }

    @ViewBuilder
    private var content: some View {
        switch widget.kind {
        case let .clock(configuration):
            ClockWidgetContentView(configuration: configuration)
        case let .itemValue(name, value, units, decimalPlaces, _, trend, lastUpdated, mappedText):
            ItemValueWidgetContentView(name: name, value: value, units: units, decimalPlaces: decimalPlaces, trend: trend, lastUpdated: lastUpdated, mappedText: mappedText)
        case let .problems(problems):
            ProblemsWidgetContentView(problems: problems)
        case let .problemsBySeverity(counts):
            ProblemsBySeverityWidgetContentView(counts: counts)
        case let .hostAvailability(breakdown):
            HostAvailabilityWidgetContentView(breakdown: breakdown)
        case let .systemInformation(serverVersion, isRunning, haNodes):
            SystemInformationWidgetContentView(serverVersion: serverVersion, isRunning: isRunning, haNodes: haNodes)
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
        case let .dataOverview(matrix):
            DataOverviewWidgetContentView(matrix: matrix)
        case let .lineChart(series, window, stacked):
            LineChartWidgetContentView(series: series, window: window, stacked: stacked)
        case let .pieChart(slices):
            PieChartWidgetContentView(slices: slices)
        case let .geomap(markers, defaultView):
            GeomapWidgetContentView(markers: markers, defaultView: defaultView)
        case let .networkMap(diagram):
            NetworkMapWidgetContentView(diagram: diagram)
        case let .mapList(maps):
            MapListWidgetContentView(maps: maps)
        case let .navigationTree(nodes):
            NavigationTreeWidgetContentView(nodes: nodes)
        case let .hostList(sections):
            HostListWidgetContentView(sections: sections)
        case let .itemList(sections):
            ItemListWidgetContentView(sections: sections)
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
    let configuration: ClockConfiguration

    var body: some View {
        switch configuration.style {
        case .analog:
            AnalogClockView(configuration: configuration)
        case .digital:
            DigitalClockView(configuration: configuration)
        }
    }
}

private struct DigitalClockView: View {
    let configuration: ClockConfiguration

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let displayedTime = context.date.addingTimeInterval(configuration.hostTimeOffset ?? 0)
            Text(displayedTime, format: configuration.timeFormat)
                .font(.system(size: 40, weight: .semibold, design: .rounded))
                .foregroundStyle(DashboardTheme.primaryText)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

/// A hand-drawn analog face, since SwiftUI has no built-in clock control.
private struct AnalogClockView: View {
    let configuration: ClockConfiguration

    var body: some View {
        GeometryReader { geometry in
            let diameter = min(geometry.size.width, geometry.size.height)

            TimelineView(.periodic(from: .now, by: 1)) { context in
                let displayedTime = context.date.addingTimeInterval(configuration.hostTimeOffset ?? 0)
                let components = configuration.calendar.dateComponents([.hour, .minute, .second], from: displayedTime)
                let hour = Double(components.hour ?? 0)
                let minute = Double(components.minute ?? 0)
                let second = Double(components.second ?? 0)

                ZStack {
                    Circle()
                        .fill(DashboardTheme.secondaryCardBackground)

                    ForEach(0..<12, id: \.self) { tick in
                        tickMark(isMajor: tick % 3 == 0, diameter: diameter)
                            .rotationEffect(.degrees(Double(tick) * 30))
                    }

                    ClockHandShape(angleDegrees: (hour.truncatingRemainder(dividingBy: 12) + minute / 60) / 12 * 360, length: diameter * 0.26)
                        .stroke(DashboardTheme.primaryText, style: StrokeStyle(lineWidth: diameter * 0.05, lineCap: .round))

                    ClockHandShape(angleDegrees: (minute + second / 60) / 60 * 360, length: diameter * 0.38)
                        .stroke(DashboardTheme.primaryText, style: StrokeStyle(lineWidth: diameter * 0.032, lineCap: .round))

                    ClockHandShape(angleDegrees: second / 60 * 360, length: diameter * 0.42)
                        .stroke(DashboardTheme.accent, style: StrokeStyle(lineWidth: diameter * 0.012, lineCap: .round))

                    Circle()
                        .fill(DashboardTheme.accent)
                        .frame(width: diameter * 0.06, height: diameter * 0.06)
                }
                .frame(width: diameter, height: diameter)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        }
    }

    /// A tick mark placed at the top of a full-diameter column so rotating the whole column around
    /// its own (default) center — which coincides with the face's center — orbits the tick to any
    /// hour position without the anchor math a bare offset-then-rotate would otherwise need.
    private func tickMark(isMajor: Bool, diameter: CGFloat) -> some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(DashboardTheme.secondaryText.opacity(isMajor ? 0.9 : 0.5))
                .frame(width: isMajor ? diameter * 0.016 : diameter * 0.01, height: diameter * 0.055)
            Spacer(minLength: 0)
        }
        .frame(height: diameter)
    }
}

/// A straight line from the center of its own bounding square out to a point `length` away at
/// `angleDegrees` (0° = 12 o'clock, increasing clockwise) — computed directly with trigonometry.
/// An earlier version composed this from `.offset` + `.rotationEffect(anchor:)`, but that anchor
/// is resolved against the shape's pre-offset bounds rather than its rendered position, so the
/// hands swept around a point well off the actual center instead of pivoting at it — verified live
/// by screenshot, where the two hour/minute hands floated free of the pivot dot entirely. Drawing
/// the line explicitly sidesteps that anchor ambiguity rather than fighting it.
private struct ClockHandShape: Shape {
    let angleDegrees: Double
    let length: CGFloat

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radians = (angleDegrees - 90) * .pi / 180
        let tip = CGPoint(x: center.x + length * cos(radians), y: center.y + length * sin(radians))

        var path = Path()
        path.move(to: center)
        path.addLine(to: tip)
        return path
    }
}

private struct ItemValueWidgetContentView: View {
    let name: String
    let value: String
    let units: String
    let decimalPlaces: Int
    let trend: ItemValueTrend?
    let lastUpdated: Date?
    let mappedText: String?

    /// Matches Zabbix's own item-value widget: the widget's `decimal_places` precision (a plain "1"
    /// reading is shown as "1.00" at the default 2), not the variable-precision formatting used for
    /// graph axis labels. When the item has a value map, its label leads with the raw value in
    /// parentheses, e.g. "Up (1.00)".
    private var displayValue: String {
        if let mappedText {
            let rawText = Double(value).map { ZabbixValueFormatting.formatItemValue($0, units: "", decimalPlaces: decimalPlaces) } ?? value
            return "\(mappedText) (\(rawText))"
        }
        guard let numericValue = Double(value) else {
            return units.isEmpty ? value : "\(value) \(units)"
        }
        return ZabbixValueFormatting.formatItemValue(numericValue, units: units, decimalPlaces: decimalPlaces)
    }

    /// Only the trend arrow is colored — verified against a live Zabbix screenshot that the
    /// value text itself stays the default white/primary color regardless of trend.
    private var trendColor: Color? {
        switch trend {
        case .up(let colorHex), .down(let colorHex):
            return Color(hex: colorHex)
        case nil:
            return nil
        }
    }

    /// A fixed "yyyy-MM-dd h:mm:ss a" pattern, matching Zabbix's own item-value widget exactly
    /// (not the device locale's date order) — verified against a live Zabbix screenshot.
    private var formattedTimestamp: String? {
        guard let lastUpdated else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd h:mm:ss a"
        return formatter.string(from: lastUpdated)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let formattedTimestamp {
                Text(formattedTimestamp)
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundStyle(DashboardTheme.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            Spacer(minLength: 0)

            HStack(spacing: 6) {
                Text(displayValue)
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(DashboardTheme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)

                if let trend, let trendColor {
                    switch trend {
                    case .up:
                        Image(systemName: "arrow.up")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(trendColor)
                    case .down:
                        Image(systemName: "arrow.down")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(trendColor)
                    }
                }
            }

            Spacer(minLength: 0)

            Text(name)
                .font(.system(size: 18, weight: .regular, design: .rounded))
                .foregroundStyle(DashboardTheme.secondaryText)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
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
            // Deliberately static, not auto-scrolling: problems are sorted newest-first, so the
            // top of the list is the most urgent thing to see. Auto-scrolling would carry
            // attention away from that toward older, already-acknowledged-by-nobody problems
            // instead — the opposite of what matters on a wall display. Whatever doesn't fit in
            // the card's height is the oldest of the batch, which is the right thing to clip.
            //
            // A TimelineView (rather than a one-shot render) is what lets a problem's "still
            // within the blink window" state age out on its own as time passes, not just when
            // the widget happens to re-fetch data.
            TimelineView(.periodic(from: .now, by: 5)) { context in
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(problems) { problem in
                        ProblemRow(problem: problem, now: context.date)
                    }
                }
            }
        }
    }
}

/// A single row in the Problems list, with its whole background tinted by severity — matching
/// real Zabbix (a colored band behind the problem text, not just a small side indicator) — and
/// blinking that background while the problem is newer than the server's configured "blink
/// period", drawing attention to a freshly-started problem the way a quiet dot never could.
private struct ProblemRow: View {
    let problem: DashboardProblem
    let now: Date

    @State private var isBlinkPhaseOn = false

    private var isNew: Bool {
        now.timeIntervalSince(problem.since) < Double(SeverityPalette.blinkPeriodSeconds)
    }

    private var severityColor: Color {
        severityIndicatorColor(for: problem.severity)
    }

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(problem.name)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(.black.opacity(0.87))
                    .lineLimit(1)

                if let host = problem.host {
                    Text(host)
                        .font(.system(size: 15, weight: .regular, design: .rounded))
                        .foregroundStyle(.black.opacity(0.65))
                        .lineLimit(1)
                }
            }

            // For Top triggers, the trailing number is how many times the trigger fired over the
            // window — the metric the widget ranks by. Absent for the live Problems list.
            if let count = problem.problemCount {
                Spacer(minLength: 4)
                Text("\(count)")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.black.opacity(0.87))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(severityColor.opacity(isNew && isBlinkPhaseOn ? 0.35 : 1))
        )
        .onAppear {
            guard isNew else { return }
            withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                isBlinkPhaseOn = true
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

    private static let nameColumnWidth: CGFloat = 160

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
        // Sized to fill whatever grid height the dashboard's own layout allotted the widget,
        // rather than sitting compact at the top with dead space below — this is an unattended
        // kiosk display, so that space is otherwise wasted rather than reclaimable by scrolling.
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 0) {
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
            .font(.system(size: 16, weight: .semibold, design: .rounded))
            .padding(.bottom, 8)

            ForEach(breakdown) { row in
                GridRow {
                    Text(row.interfaceTypeName)
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .foregroundStyle(DashboardTheme.secondaryText)
                        .frame(width: Self.nameColumnWidth, alignment: .leading)
                        .lineLimit(1)

                    ForEach(Self.columns, id: \.title) { column in
                        Text("\(row[keyPath: column.keyPath])")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(DashboardTheme.primaryText)
                    }

                    Text("\(row.total)")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(DashboardTheme.primaryText)
                }
                .frame(maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

private struct SystemInformationWidgetContentView: View {
    let serverVersion: String
    let isRunning: Bool
    let haNodes: [SystemHANode]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if haNodes.isEmpty {
                statusRow(label: "Zabbix server is running", value: isRunning ? "Yes" : "No", color: isRunning ? .green : .red)
                statusRow(label: "Zabbix server version", value: serverVersion, color: DashboardTheme.secondaryText)
            } else {
                // "High availability nodes" mode: one row per cluster node with its status.
                ForEach(haNodes) { node in
                    statusRow(label: node.name, value: node.statusLabel, color: node.isActive ? .green : DashboardTheme.secondaryText)
                }
            }
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
