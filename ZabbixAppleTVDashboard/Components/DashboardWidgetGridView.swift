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

    /// When `true`, an overflowing page scrolls itself; when `false`, it holds still and is scrolled
    /// by hand with the remote's directional pad.
    var autoScrollEnabled: Bool = true

    /// Invoked when the remote's Play/Pause button is pressed — toggles the scroll mode.
    var onToggleAutoScroll: () -> Void = {}

    /// Below this, a widget stops being legible — a graph needs room for its title, axes, and
    /// legend. Some Zabbix dashboard pages configure far more total grid rows than fit in one
    /// screen (verified live: one page stacks 13 full-width graphs across 63 rows), and dividing
    /// the screen height by the row count for a page like that shrinks every widget to a few
    /// points tall with everything overlapping. Rather than keep shrinking past this floor, the
    /// page's content grows taller than the screen and auto-scrolls instead (see below).
    private static let minimumRowHeight: CGFloat = 60

    /// How fast an overflowing page auto-scrolls, in points per second — an unattended kiosk display
    /// has no one at the remote, so this is the only way every widget on a page like that actually
    /// gets seen during its time on screen rather than just the first screenful.
    private static let autoScrollPointsPerSecond: CGFloat = 40

    /// Auto-scroll is advanced in small per-frame steps (rather than one long animation) so that
    /// flipping to manual mid-scroll freezes the page exactly where it is and the first remote nudge
    /// continues from there, with no jump between the animated position and the model offset.
    private static let autoScrollFramesPerSecond: Double = 30
    private static var autoScrollFrameNanoseconds: UInt64 { UInt64(1_000_000_000 / autoScrollFramesPerSecond) }
    private static var autoScrollPointsPerFrame: CGFloat { autoScrollPointsPerSecond / CGFloat(autoScrollFramesPerSecond) }

    /// Pause before auto-scroll begins, so the first widgets are readable before the page moves.
    private static let autoScrollStartPauseNanoseconds: UInt64 = 3 * 1_000_000_000

    /// How much of the visible height one remote nudge scrolls in manual mode — a chunk big enough
    /// to make progress, small enough to keep context between presses.
    private static let manualScrollFraction: CGFloat = 0.25

    @State private var scrollOffset: CGFloat = 0
    @FocusState private var isFocused: Bool

    /// Keeps a scroll offset within the scrollable range: never above the content's overflow, never
    /// below zero (and pinned to zero when the content fits, so a nudge on a non-overflowing page
    /// does nothing).
    static func clampedScrollOffset(_ proposed: CGFloat, overflow: CGFloat) -> CGFloat {
        min(max(proposed, 0), max(overflow, 0))
    }

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
            // Focusable so the remote's Play/Pause (toggle mode) and directional (manual scroll)
            // commands route here — the dashboard's own cards aren't focusable, so this is the only
            // focus target. The focus effect is suppressed so the whole page doesn't get a highlight.
            .focusable()
            .focusEffectDisabled()
            .focused($isFocused)
            .onAppear { isFocused = true }
            .onPlayPauseCommand(perform: onToggleAutoScroll)
            .onMoveCommand { direction in
                guard !autoScrollEnabled else { return }
                let step = geometry.size.height * Self.manualScrollFraction
                switch direction {
                case .up:
                    withAnimation(.easeOut(duration: 0.2)) {
                        scrollOffset = Self.clampedScrollOffset(scrollOffset - step, overflow: overflow)
                    }
                case .down:
                    withAnimation(.easeOut(duration: 0.2)) {
                        scrollOffset = Self.clampedScrollOffset(scrollOffset + step, overflow: overflow)
                    }
                default:
                    break
                }
            }
            .task(id: "\(overflow)|\(autoScrollEnabled)") {
                guard autoScrollEnabled, overflow > 0 else { return }

                // A short pause so the first widgets are readable, then a slow, steady crawl to the
                // bottom in small per-frame steps (see `autoScrollPointsPerFrame`), holding there
                // until the page rotates. Stepping keeps the model offset equal to what's on screen,
                // so a switch to manual freezes exactly here.
                try? await Task.sleep(nanoseconds: Self.autoScrollStartPauseNanoseconds)
                while !Task.isCancelled && scrollOffset < overflow {
                    try? await Task.sleep(nanoseconds: Self.autoScrollFrameNanoseconds)
                    guard !Task.isCancelled else { return }
                    scrollOffset = min(scrollOffset + Self.autoScrollPointsPerFrame, overflow)
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
        case let .systemInformation(rows, haNodes):
            SystemInformationWidgetContentView(rows: rows, haNodes: haNodes)
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
        case let .itemHistory(series, showTimestamp):
            ItemHistoryWidgetContentView(series: series, showTimestamp: showTimestamp)
        case let .dataOverview(matrix):
            DataOverviewWidgetContentView(matrix: matrix)
        case let .lineChart(series, window, stacked, showLegend, showLegendStats, yMin, yMax):
            LineChartWidgetContentView(series: series, window: window, stacked: stacked, showLegend: showLegend, showLegendStats: showLegendStats, yMin: yMin, yMax: yMax)
        case let .pieChart(slices, isDonut):
            PieChartWidgetContentView(slices: slices, isDonut: isDonut)
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
        case .referencedObjectUnavailable:
            // Zabbix's own wording for a widget whose referenced object is deleted or not visible
            // to the logged-in account — kept verbatim so any account sees the same state here that
            // Zabbix's frontend would show it.
            Text("No permissions to referred object or it does not exist!")
                .font(.system(size: 18, weight: .regular, design: .rounded))
                .foregroundStyle(DashboardTheme.secondaryText)
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
        // Zabbix's item-value layout is a centered stack — time on top, the bold value (with its
        // trend arrow beside it) in the middle, the description at the bottom — not left-aligned.
        VStack(spacing: 4) {
            if let formattedTimestamp {
                Text(formattedTimestamp)
                    .font(.system(size: 15, weight: .regular, design: .rounded))
                    .foregroundStyle(DashboardTheme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                Text(displayValue)
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundStyle(DashboardTheme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)

                if let trend, let trendColor {
                    switch trend {
                    case .up:
                        Image(systemName: "arrow.up")
                            .font(.system(size: 30, weight: .bold))
                            .foregroundStyle(trendColor)
                    case .down:
                        Image(systemName: "arrow.down")
                            .font(.system(size: 30, weight: .bold))
                            .foregroundStyle(trendColor)
                    }
                }
            }

            Spacer(minLength: 0)

            Text(name)
                .font(.system(size: 20, weight: .regular, design: .rounded))
                .foregroundStyle(DashboardTheme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
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

                // Event tags (capped by the widget's show_tags), as small chips on the severity band.
                if !problem.tags.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(problem.tags) { tag in
                            Text(tag.label)
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(.black.opacity(0.72))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(.black.opacity(0.12)))
                                .lineLimit(1)
                        }
                    }
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
                // Zabbix's header cells are filled color blocks (green/red/orange/gray) with dark
                // text, not colored text on the card background.
                ForEach(Self.columns, id: \.title) { column in
                    Text(column.title)
                        .foregroundStyle(.black.opacity(0.8))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 3, style: .continuous).fill(column.color))
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
    let rows: [SystemInfoRow]
    let haNodes: [SystemHANode]

    private static func color(for tint: SystemInfoTint) -> Color {
        switch tint {
        case .normal: DashboardTheme.primaryText
        case .green: .green
        case .red: .red
        case .gray: DashboardTheme.secondaryText
        }
    }

    var body: some View {
        if haNodes.isEmpty {
            // Zabbix's Parameter / Value / Details table. Rows an account can't compute (missing
            // permission for a count) are simply absent, matching how the API scopes its answers.
            AutoScrollingContent {
                Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 7) {
                    GridRow {
                        ForEach(["Parameter", "Value", "Details"], id: \.self) { header in
                            Text(header)
                                .font(.system(size: 13, weight: .regular, design: .rounded))
                                .foregroundStyle(DashboardTheme.secondaryText)
                        }
                    }

                    ForEach(rows) { row in
                        GridRow {
                            Text(row.parameter)
                                .font(.system(size: 15, weight: .regular, design: .rounded))
                                .foregroundStyle(DashboardTheme.primaryText)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Text(row.value)
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .foregroundStyle(Self.color(for: row.valueTint))

                            // Colored segments concatenated into one Text so they wrap as a unit.
                            row.details.reduce(Text("")) { partial, segment in
                                partial + Text(segment.text).foregroundStyle(Self.color(for: segment.tint))
                            }
                            .font(.system(size: 15, weight: .regular, design: .rounded))
                        }
                    }
                }
            }
        } else {
            // "High availability nodes" mode: one row per cluster node with its status.
            VStack(alignment: .leading, spacing: 10) {
                ForEach(haNodes) { node in
                    HStack(spacing: 6) {
                        Text("\(node.name):")
                            .font(.system(size: 16, weight: .regular, design: .rounded))
                            .foregroundStyle(DashboardTheme.secondaryText)

                        Text(node.statusLabel)
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(node.isActive ? .green : DashboardTheme.secondaryText)
                    }
                }
            }
        }
    }
}

/// Maps a Zabbix problem severity (0 = not classified, 5 = disaster) to this server's own
/// configured indicator color (see `SeverityPalette`), rather than a fixed guess.
@MainActor
func severityIndicatorColor(for severity: Int) -> Color {
    SeverityPalette.color(for: severity)
}
