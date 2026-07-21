//
//  DashboardWidgetContentViews.swift
//  ZabbixAppleTVDashboard
//
//  Created by Codex on 7/7/26.
//

import Charts
import MapKit
import SwiftUI
import UIKit

struct GeomapWidgetContentView: View {
    let markers: [GeoMapMarker]
    var defaultView: GeoMapView? = nil

    private var cameraPosition: MapCameraPosition {
        // Honor the widget's configured initial view when set: center on it and derive a MapKit span
        // from the web-map zoom level (each zoom step roughly halves the visible degrees).
        if let view = defaultView {
            let degrees = min(max(360 / pow(2, view.zoom), 0.002), 180)
            return .region(MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: view.latitude, longitude: view.longitude),
                span: MKCoordinateSpan(latitudeDelta: degrees, longitudeDelta: degrees)
            ))
        }

        guard !markers.isEmpty else {
            return .automatic
        }

        let latitudes = markers.map(\.latitude)
        let longitudes = markers.map(\.longitude)
        let center = CLLocationCoordinate2D(
            latitude: (latitudes.min()! + latitudes.max()!) / 2,
            longitude: (longitudes.min()! + longitudes.max()!) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max((latitudes.max()! - latitudes.min()!) * 1.4, 1),
            longitudeDelta: max((longitudes.max()! - longitudes.min()!) * 1.4, 1)
        )
        return .region(MKCoordinateRegion(center: center, span: span))
    }

    var body: some View {
        if markers.isEmpty {
            Text("No hosts with valid coordinates")
                .font(.system(size: 16, weight: .regular, design: .rounded))
                .foregroundStyle(DashboardTheme.secondaryText)
        } else {
            Map(initialPosition: cameraPosition) {
                ForEach(markers) { marker in
                    Marker(marker.hostName, coordinate: CLLocationCoordinate2D(latitude: marker.latitude, longitude: marker.longitude))
                        .tint(marker.severity == 0 ? .green : severityIndicatorColor(for: marker.severity))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: DashboardTheme.cardCornerRadius, style: .continuous))
        }
    }
}

struct NetworkMapWidgetContentView: View {
    let diagram: NetworkMapDiagram

    private var backgroundImage: UIImage? {
        diagram.backgroundImageData.flatMap { UIImage(data: $0) }
    }

    var body: some View {
        // A map with only a background/shapes (a floor plan) is still a real map — bail to the
        // empty note only when there is truly nothing to draw.
        if diagram.elements.isEmpty && backgroundImage == nil && diagram.shapes.isEmpty && diagram.freeLines.isEmpty {
            Text("This map has no elements")
                .font(.system(size: 16, weight: .regular, design: .rounded))
                .foregroundStyle(DashboardTheme.secondaryText)
        } else {
            // One uniform scale keeps the background and every drawn coordinate in register the
            // way the frontend scales its maps (per-axis stretching drifted elements off a
            // background whose aspect differs from the widget's), with the canvas centered.
            GeometryReader { geometry in
                let scale = min(
                    geometry.size.width / CGFloat(max(diagram.width, 1)),
                    geometry.size.height / CGFloat(max(diagram.height, 1))
                )
                let canvasWidth = CGFloat(diagram.width) * scale
                let canvasHeight = CGFloat(diagram.height) * scale

                ZStack(alignment: .topLeading) {
                    if let backgroundImage {
                        Image(uiImage: backgroundImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: canvasWidth, height: canvasHeight)
                    }

                    Canvas { context, _ in
                        // Drawn shapes under everything: fill, border, centered label.
                        for shape in diagram.shapes {
                            let rect = CGRect(x: CGFloat(shape.x) * scale, y: CGFloat(shape.y) * scale, width: CGFloat(shape.width) * scale, height: CGFloat(shape.height) * scale)
                            let path = shape.isEllipse ? Path(ellipseIn: rect) : Path(rect)
                            if let fill = shape.backgroundColorHex.flatMap({ Color(hex: $0) }) {
                                context.fill(path, with: .color(fill))
                            }
                            if let border = shape.borderColorHex.flatMap({ Color(hex: $0) }) {
                                context.stroke(path, with: .color(border), lineWidth: max(CGFloat(shape.borderWidth) * scale, 1))
                            }
                            if !shape.text.isEmpty {
                                context.draw(
                                    Text(shape.text)
                                        .font(.system(size: max(CGFloat(shape.fontSize) * scale, 7), weight: .medium, design: .rounded))
                                        .foregroundColor(shape.fontColorHex.flatMap { Color(hex: $0) } ?? DashboardTheme.primaryText),
                                    at: CGPoint(x: rect.midX, y: rect.midY)
                                )
                            }
                        }

                        for line in diagram.freeLines {
                            var path = Path()
                            path.move(to: CGPoint(x: CGFloat(line.x1) * scale, y: CGFloat(line.y1) * scale))
                            path.addLine(to: CGPoint(x: CGFloat(line.x2) * scale, y: CGFloat(line.y2) * scale))
                            context.stroke(path, with: .color(line.colorHex.flatMap { Color(hex: $0) } ?? .gray), lineWidth: max(CGFloat(line.width) * scale, 1))
                        }

                        for link in diagram.links {
                            var path = Path()
                            path.move(to: CGPoint(x: CGFloat(link.fromX) * scale, y: CGFloat(link.fromY) * scale))
                            path.addLine(to: CGPoint(x: CGFloat(link.toX) * scale, y: CGFloat(link.toY) * scale))
                            context.stroke(path, with: .color(Color(hex: link.colorHex) ?? .gray), lineWidth: 2)
                        }
                    }
                    .frame(width: canvasWidth, height: canvasHeight)

                    ForEach(diagram.elements) { element in
                        VStack(spacing: 2) {
                            NetworkMapElementIconView(element: element)
                            Text(element.label)
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(DashboardTheme.primaryText)
                                .lineLimit(1)
                                .fixedSize()
                        }
                        .position(x: CGFloat(element.x) * scale, y: CGFloat(element.y) * scale)
                    }
                }
                .frame(width: canvasWidth, height: canvasHeight)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        }
    }
}

/// Renders a map element's actual device-type icon (switch, router, cloud, ...) when one was
/// resolved, with a small severity-colored status badge — falling back to a plain colored dot
/// (the old behavior) if no icon image is available.
private struct NetworkMapElementIconView: View {
    let element: NetworkMapElement

    /// Severity 0 means "no active problem", shown as green — distinct from Zabbix's "Not
    /// classified" severity level, which is an uncategorized problem, not a healthy state.
    private var statusColor: Color {
        element.severity == 0 ? .green : severityIndicatorColor(for: element.severity)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if let iconImageData = element.iconImageData, let uiImage = UIImage(data: iconImageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 28, height: 28)

                Circle()
                    .fill(statusColor)
                    .frame(width: 9, height: 9)
                    .overlay(Circle().stroke(DashboardTheme.background, lineWidth: 1.5))
                    .offset(x: 3, y: -3)
            } else {
                Circle()
                    .fill(statusColor)
                    .frame(width: 14, height: 14)
            }
        }
        .frame(width: 28, height: 28)
    }
}

struct MapListWidgetContentView: View {
    let maps: [MapListEntry]

    var body: some View {
        if maps.isEmpty {
            Text("No maps available")
                .font(.system(size: 16, weight: .regular, design: .rounded))
                .foregroundStyle(DashboardTheme.secondaryText)
        } else {
            AutoScrollingContent {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(maps) { map in
                        Text(map.name)
                            .font(.system(size: 16, weight: .medium, design: .rounded))
                            .foregroundStyle(DashboardTheme.primaryText)
                            .lineLimit(1)
                    }
                }
            }
        }
    }
}

struct NavigationTreeWidgetContentView: View {
    let nodes: [NavTreeNode]

    var body: some View {
        if nodes.isEmpty {
            Text("No navigation tree configured")
                .font(.system(size: 16, weight: .regular, design: .rounded))
                .foregroundStyle(DashboardTheme.secondaryText)
        } else {
            AutoScrollingContent {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(nodes) { node in
                        HStack(spacing: 8) {
                            // Folder glyph for grouping nodes, a map glyph for nodes linking a map.
                            Image(systemName: node.linksToMap ? "map" : "folder")
                                .font(.system(size: 14))
                                .foregroundStyle(DashboardTheme.secondaryText)

                            Text(node.name)
                                .font(.system(size: 16, weight: node.depth == 0 ? .semibold : .regular, design: .rounded))
                                .foregroundStyle(DashboardTheme.primaryText)
                                .lineLimit(1)

                            // Worst-problem severity for the node's map (or its subtree). No dot when
                            // everything is OK, so a healthy tree stays visually quiet.
                            if node.severity > 0 {
                                Spacer(minLength: 4)
                                Circle()
                                    .fill(severityIndicatorColor(for: node.severity))
                                    .frame(width: 10, height: 10)
                            }
                        }
                        // Indent by depth so the hierarchy reads as a tree.
                        .padding(.leading, CGFloat(node.depth) * 18)
                    }
                }
            }
        }
    }
}

struct HostListWidgetContentView: View {
    let sections: [HostListSection]

    var body: some View {
        if sections.allSatisfy({ $0.hosts.isEmpty }) {
            Text("No hosts match this widget's filters")
                .font(.system(size: 16, weight: .regular, design: .rounded))
                .foregroundStyle(DashboardTheme.secondaryText)
        } else {
            AutoScrollingContent {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(sections) { section in
                        // A `group_by` heading, when grouped (empty title = a single flat list).
                        if !section.title.isEmpty {
                            Text(section.title)
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(DashboardTheme.secondaryText)
                                .padding(.top, 2)
                        }
                        ForEach(section.hosts) { host in
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(host.maxSeverity == 0 ? Color.green : severityIndicatorColor(for: host.maxSeverity))
                                    .frame(width: 10, height: 10)

                                Text(host.name)
                                    .font(.system(size: 16, weight: .medium, design: .rounded))
                                    .foregroundStyle(DashboardTheme.primaryText)
                                    .lineLimit(1)

                                if host.problemCount > 0 {
                                    Spacer()
                                    Text("\(host.problemCount)")
                                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                                        .foregroundStyle(DashboardTheme.secondaryText)
                                }
                            }
                            .padding(.leading, section.title.isEmpty ? 0 : 10)
                        }
                    }
                }
            }
        }
    }
}

struct ItemListWidgetContentView: View {
    let sections: [ItemListSection]

    var body: some View {
        if sections.allSatisfy({ $0.items.isEmpty }) {
            Text("No items match this widget's filters")
                .font(.system(size: 16, weight: .regular, design: .rounded))
                .foregroundStyle(DashboardTheme.secondaryText)
        } else {
            AutoScrollingContent {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(sections) { section in
                        // When grouped by host, the section title is the host name, so each item's
                        // own host line is redundant and dropped.
                        if !section.title.isEmpty {
                            Text(section.title)
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(DashboardTheme.secondaryText)
                                .padding(.top, 2)
                        }
                        ForEach(section.items) { item in
                            HStack {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(item.name)
                                        .font(.system(size: 15, weight: .medium, design: .rounded))
                                        .foregroundStyle(DashboardTheme.primaryText)
                                        .lineLimit(1)
                                    if section.title.isEmpty {
                                        Text(item.hostName)
                                            .font(.system(size: 12, weight: .regular, design: .rounded))
                                            .foregroundStyle(DashboardTheme.secondaryText)
                                            .lineLimit(1)
                                    }
                                }
                                Spacer()
                                Text(item.units.isEmpty ? item.lastValue : "\(item.lastValue) \(item.units)")
                                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                                    .foregroundStyle(DashboardTheme.accent)
                            }
                            .padding(.leading, section.title.isEmpty ? 0 : 10)
                        }
                    }
                }
            }
        }
    }
}

struct SLAReportWidgetContentView: View {
    let entries: [SLAReportEntry]

    private func sliColor(for meetsTarget: Bool?) -> Color {
        switch meetsTarget {
        case true: .green
        case false: .red
        case nil: DashboardTheme.primaryText
        }
    }

    var body: some View {
        if entries.isEmpty {
            Text("No SLA selected, or no SLAs configured")
                .font(.system(size: 16, weight: .regular, design: .rounded))
                .foregroundStyle(DashboardTheme.secondaryText)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(entries) { entry in
                    HStack(spacing: 10) {
                        Text(entry.name)
                            .font(.system(size: 17, weight: .medium, design: .rounded))
                            .foregroundStyle(DashboardTheme.primaryText)
                            .lineLimit(1)

                        Spacer(minLength: 4)

                        if let sli = entry.achievedSLI {
                            Text(sli)
                                .font(.system(size: 17, weight: .bold, design: .rounded))
                                .foregroundStyle(sliColor(for: entry.meetsTarget))
                        }

                        Text("Target \(entry.targetSLO)")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(DashboardTheme.secondaryText)
                    }
                }
            }
        }
    }
}

struct LineChartWidgetContentView: View {
    let series: [ChartSeries]
    let window: ChartTimeWindow
    var stacked: Bool = false
    var showLegend: Bool = true
    var showLegendStats: Bool = false
    var yMin: Double? = nil
    var yMax: Double? = nil
    var triggerLines: [GraphTriggerLine] = []
    var axisStyle: GraphAxisStyle = .svg

    /// The muted red Zabbix paints the classic image graph's window-boundary timestamps with.
    private static let boundaryLabelColor = Color(hex: "B85C5C") ?? .red

    private var units: String { series.first?.units ?? "" }

    /// The chart's Y-axis range. A fixed bound (`lefty_min`/`lefty_max`, or a classic graph's fixed
    /// axis) wins: an unset lower bound defaults to 0, an unset upper bound to the data's own max.
    /// With no fixed bounds, the axis auto-scales to the data the way Zabbix's own graphs do — the
    /// lower bound rides up near the data's minimum instead of anchoring at zero, so a series
    /// hovering around 14 GB draws as a readable band (13.85–14.15) rather than a solid block over
    /// a 0-based axis. Data at or below zero, and stacked graphs (whose baseline is the sum
    /// floor), keep the zero anchor.
    private var yScaleDomain: ClosedRange<Double>? {
        if yMin != nil || yMax != nil {
            let dataMax = series.flatMap(\.points).compactMap(\.value).max() ?? 0
            let lower = yMin ?? 0
            let upper = yMax ?? max(dataMax, lower)
            return lower <= upper ? lower...upper : lower...(lower + 1)
        }

        guard !stacked else { return nil }
        // Trigger lines participate in the auto range, as on Zabbix's own graphs — a 90% threshold
        // stays visible over data hugging zero.
        let values = series.flatMap(\.points).compactMap(\.value) + triggerLines.map(\.value)
        guard let minValue = values.min(), let maxValue = values.max(), minValue > 0 else { return nil }
        let span = maxValue - minValue
        let padding = span > 0 ? span * 0.05 : max(maxValue * 0.01, 0.5)
        return max(0, minValue - padding)...(maxValue + padding)
    }

    /// Where the area fill anchors: the resolved axis floor. Pinning to 0 when the axis floor is
    /// higher would silently drag the whole scale back down to zero (marks participate in Swift
    /// Charts' automatic domain), undoing the auto-scaled minimum above.
    private var areaBaseline: Double {
        yScaleDomain?.lowerBound ?? 0
    }

    private var yAxisScale: ZabbixValueFormatting.Scale {
        // Scale labels to the fixed axis max when one is set, so a pinned 2.5 Gbps axis reads in G
        // rather than being scaled from the data's own (smaller) peak.
        let dataMax = series.flatMap(\.points).compactMap(\.value).max() ?? 0
        return ZabbixValueFormatting.scale(forMaxMagnitude: max(dataMax, yMax ?? 0), units: units)
    }

    /// One drawable run of a series between the `nil` breaks that mark gaps in its data. Each
    /// segment gets a unique grouping id so Swift Charts draws it as its own line — which is what
    /// makes the line break across a gap rather than interpolate straight over it — while all of a
    /// series' segments still map to that series' single color. (Swift Charts' closure-form
    /// `.value()` can't take an optional to signal a gap, so splitting into segments is how the
    /// blanks get drawn.)
    private struct ChartSegment: Identifiable {
        let id: String
        let seriesName: String
        let colorHex: String
        let fillOpacity: Double
        let points: [ChartPoint]
    }

    /// Splits every series into its non-`nil` runs. A `nil`-valued point (a gap marker inserted for
    /// a stretch the item reported no data) ends the current run and starts a new one after it.
    private var segments: [ChartSegment] {
        var result: [ChartSegment] = []
        for line in series {
            var runIndex = 0
            var current: [ChartPoint] = []

            func flush() {
                guard !current.isEmpty else { return }
                result.append(ChartSegment(id: "\(line.id)#\(runIndex)", seriesName: line.name, colorHex: line.colorHex, fillOpacity: line.fillOpacity, points: current))
                runIndex += 1
                current = []
            }

            for point in line.points {
                if point.value == nil { flush() } else { current.append(point) }
            }
            flush()
        }
        return result
    }

    /// Builds one point's marks in their own function (rather than inline in the `Chart` closure)
    /// so the type checker has a small, isolated expression to solve instead of the whole nested
    /// `Chart { ForEach { ForEach { ... } } }` tree at once — the inline form timed out entirely.
    ///
    /// `foregroundStyle(by:)` (a plottable grouping value, not a bare `Color`) is what tells Swift
    /// Charts these points belong to distinct lines — without it, points from different segments
    /// interleave into one zigzagging path sorted by x-position instead of staying separate. Each
    /// segment's id groups it as its own line so gaps break cleanly.
    @ChartContentBuilder
    private func marks(for point: ChartPoint, in segment: ChartSegment) -> some ChartContent {
        // Explicit yStart/yEnd (rather than the single-`y` initializer) bypasses Swift Charts'
        // automatic stacking baseline — with a plain `y:` value, grouping by `foregroundStyle(by:)`
        // makes each series' baseline the sum of the ones before it (as if plotting composition),
        // which was inflating the visible peak to the sum of every series rather than each one's
        // own value. yStart anchors at the resolved axis floor (`areaBaseline`), not a hardcoded 0
        // — a 0 mark would drag an auto-scaled axis back down to zero. `point.value` is non-nil
        // within a segment by construction.
        AreaMark(x: .value("Time", point.date), yStart: .value("Baseline", areaBaseline), yEnd: .value(segment.seriesName, point.value ?? 0))
            .foregroundStyle(by: .value("Series", segment.id))
            .opacity(segment.fillOpacity)

        LineMark(x: .value("Time", point.date), y: .value(segment.seriesName, point.value ?? 0))
            .foregroundStyle(by: .value("Series", segment.id))
    }

    /// A stacked-area mark: the single-`y` initializer with `stacking: .standard`, grouped by series
    /// (not gap-segment), is exactly what makes Swift Charts pile each series on the one before it —
    /// the composition the non-stacked path deliberately avoids. Gaps interpolate here (a stacked
    /// area reads a missing sample as no contribution) rather than breaking the line.
    @ChartContentBuilder
    private func stackedMark(for point: ChartPoint, in line: ChartSeries) -> some ChartContent {
        AreaMark(x: .value("Time", point.date), y: .value("Value", point.value ?? 0), stacking: .standard)
            .foregroundStyle(by: .value("Series", line.id))
            .opacity(line.fillOpacity)
    }

    /// A trigger's constant threshold as Zabbix draws it: a dashed horizontal rule in the
    /// trigger's severity color.
    @ChartContentBuilder
    private var triggerLineMarks: some ChartContent {
        ForEach(triggerLines) { line in
            RuleMark(y: .value("Trigger", line.value))
                .foregroundStyle(Color(hex: line.colorHex) ?? .orange)
                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
        }
    }

    private var segmentedChart: some View {
        let segments = segments
        return Chart {
            ForEach(segments) { segment in
                ForEach(segment.points) { point in
                    marks(for: point, in: segment)
                }
            }

            triggerLineMarks
        }
        // Every segment of a series maps to that series' one color, so a broken-up line stays a
        // single visual color across its gaps.
        .chartForegroundStyleScale(
            domain: segments.map(\.id),
            range: segments.map { Color(hex: $0.colorHex) ?? DashboardTheme.accent }
        )
    }

    private var stackedChart: some View {
        Chart {
            ForEach(series) { line in
                ForEach(line.points.filter { $0.value != nil }) { point in
                    stackedMark(for: point, in: line)
                }
            }

            triggerLineMarks
        }
        .chartForegroundStyleScale(
            domain: series.map(\.id),
            range: series.map { Color(hex: $0.colorHex) ?? DashboardTheme.accent }
        )
    }

    /// The Y grid Zabbix would draw for this chart at this height: nice steps in displayed units,
    /// auto bounds rounded outward to whole steps, and the per-label decimals the step calls for.
    /// svggraph packs a labeled row about every 55pt ("14.095 GB" steps of 0.005); the classic
    /// image graph keeps rows sparse (about every 120pt — a CPU graph reads just 0 / 50 / 100 %).
    /// Nil means the data gave nothing to grid (stacked charts keep Swift Charts' automatic axis).
    private func resolvedYAxis(plotHeight: CGFloat) -> GraphAxisMath.YAxis? {
        let fixedBounds = yMin != nil || yMax != nil
        let lower: Double
        let upper: Double
        if let domain = yScaleDomain {
            lower = domain.lowerBound
            upper = domain.upperBound
        } else if !stacked {
            let values = series.flatMap(\.points).compactMap(\.value) + triggerLines.map(\.value)
            guard let maxValue = values.max() else { return nil }
            lower = min(0, values.min() ?? 0)
            upper = maxValue
        } else {
            return nil
        }

        let rowHeight: CGFloat = axisStyle == .svg ? 55 : 120
        let intervals = max(2, Int((plotHeight / rowHeight).rounded()))
        return GraphAxisMath.yAxis(
            lower: lower,
            upper: upper,
            fixedBounds: fixedBounds,
            targetIntervals: intervals,
            scaleDivisor: yAxisScale.divisor
        )
    }

    /// One Y-axis label with the grid's fixed decimals — "14.095 GB", "50 %" — matching Zabbix,
    /// which keeps trailing zeros on axis labels ("14.100 GB") so rows line up.
    private func yAxisLabelText(_ rawValue: Double, decimals: Int) -> String {
        let scale = yAxisScale
        let number = String(format: "%.\(decimals)f", rawValue / scale.divisor)
        let suffix = "\(scale.prefix)\(units)"
        return suffix.isEmpty ? number : "\(number) \(suffix)"
    }

    private static func timeLabel(_ date: Date, format: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = format
        return formatter.string(from: date)
    }

    /// Axis/legend configuration shared by the stacked and non-stacked charts. Needs the plot's
    /// size (from the enclosing GeometryReader) to pick Zabbix-like grid densities.
    private func styled(_ chart: some View, plotSize: CGSize) -> some View {
        let resolvedAxis = resolvedYAxis(plotHeight: plotSize.height)
        return chart
            // Swift Charts' built-in legend doesn't wrap long labels within the card's actual width,
            // so it's hidden in favor of the wrapping `ChartLegendView` below.
            .chartLegend(.hidden)
            // Pin the x-axis to the widget's full configured window rather than auto-fitting to the
            // data, so a period with no data reads as blank space at the right spot.
            .chartXScale(domain: window.start...window.end)
            .chartXAxis {
                if axisStyle == .svg {
                    // svggraph divides the window into even cells (~100pt) and labels each
                    // boundary horizontally with a zero-padded, date-prefixed time:
                    // "7-19 08:45 PM" (verified against the live QA svggraph).
                    let intervals = max(2, Int(plotSize.width / 100))
                    AxisMarks(values: GraphAxisMath.classicTimeTicks(start: window.start, end: window.end, intervals: intervals)) { value in
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel {
                            if let date = value.as(Date.self) {
                                Text(Self.timeLabel(date, format: "M-d hh:mm a"))
                                    .font(.system(size: 12, weight: .regular, design: .rounded))
                                    .foregroundStyle(DashboardTheme.secondaryText)
                            }
                        }
                    }
                } else {
                    // The classic image graph packs a rotated label at every nice time step
                    // ("08:46 PM" each 2 minutes on an hour graph) and brackets the window with
                    // red boundary timestamps that carry the date (verified live).
                    let step = GraphAxisMath.svgTimeStep(windowSeconds: window.end.timeIntervalSince(window.start), plotWidth: plotSize.width)
                    AxisMarks(values: GraphAxisMath.svgTimeTicks(start: window.start, end: window.end, step: step)) { value in
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel(anchor: .topTrailing) {
                            if let date = value.as(Date.self) {
                                Self.rotatedAxisLabel(Self.timeLabel(date, format: "hh:mm a"), color: DashboardTheme.secondaryText)
                            }
                        }
                    }
                    AxisMarks(values: [window.start, window.end]) { value in
                        AxisValueLabel(anchor: .topTrailing) {
                            if let date = value.as(Date.self) {
                                Self.rotatedAxisLabel(Self.timeLabel(date, format: "MM-dd hh:mm a"), color: Self.boundaryLabelColor)
                            }
                        }
                    }
                }
            }
            .chartYAxis {
                if let resolvedAxis {
                    AxisMarks(position: .leading, values: resolvedAxis.ticks) { value in
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel {
                            if let rawValue = value.as(Double.self) {
                                Text(yAxisLabelText(rawValue, decimals: resolvedAxis.decimals))
                                    .font(.system(size: 13, weight: .regular, design: .rounded))
                            }
                        }
                    }
                } else {
                    let scale = yAxisScale
                    AxisMarks(position: .leading) { value in
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel {
                            if let rawValue = value.as(Double.self) {
                                Text(ZabbixValueFormatting.format(rawValue, units: units, scale: scale))
                                    .font(.system(size: 13, weight: .regular, design: .rounded))
                            }
                        }
                    }
                }
            }
            // Pin the Y-axis to the grid's (outward-rounded) bounds, so the top and bottom
            // gridlines land exactly on labeled steps the way Zabbix draws them.
            .chartYScaleIfSet(resolvedAxis.map { $0.lower...$0.upper } ?? yScaleDomain)
    }

    /// A vertically rotated svggraph axis label. The fixed slot (width for one text line, height
    /// for the rotated text's length) is what reserves the tall axis band under the plot — the
    /// rotation itself doesn't change layout size.
    private static let svgAxisLabelSlotHeight: CGFloat = 74

    private static func rotatedAxisLabel(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .regular, design: .rounded))
            .foregroundStyle(color)
            .fixedSize()
            .rotationEffect(.degrees(-90), anchor: .center)
            .frame(width: 13, height: svgAxisLabelSlotHeight)
    }

    var body: some View {
        if series.allSatisfy({ $0.points.isEmpty }) {
            Text("No data for this time period")
                .font(.system(size: 16, weight: .regular, design: .rounded))
                .foregroundStyle(DashboardTheme.secondaryText)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                GeometryReader { geometry in
                    if stacked {
                        styled(stackedChart, plotSize: geometry.size)
                    } else {
                        styled(segmentedChart, plotSize: geometry.size)
                    }
                }

                // Zabbix shows the legend whenever it's enabled — including single-series graphs,
                // where the color key is what names the series ("— BSD-DNS1: Available memory").
                if showLegend {
                    ChartLegendView(series: series, showStats: showLegendStats, triggerLines: triggerLines)
                }
            }
        }
    }
}

private extension View {
    /// Applies a fixed Y-axis domain when one is provided; otherwise leaves the chart to auto-scale.
    @ViewBuilder
    func chartYScaleIfSet(_ domain: ClosedRange<Double>?) -> some View {
        if let domain {
            chartYScale(domain: domain)
        } else {
            self
        }
    }
}

/// A wrapping legend for `LineChartWidgetContentView`, since Swift Charts' built-in legend can
/// run long labels (full Zabbix item names) off the edge of the card instead of wrapping them.
///
/// Two forms, matching Zabbix's two graph legends:
/// - names-only (svggraph): a short color dash + the series name, wrapping across columns;
/// - stats (classic graph): one row per series with `[avg]` and its last/min/avg/max over the
///   drawn window, under a small header row, exactly as Zabbix's classic-graph legend tabulates.
private struct ChartLegendView: View {
    let series: [ChartSeries]
    var showStats: Bool = false
    var triggerLines: [GraphTriggerLine] = []

    private let columns = [GridItem(.adaptive(minimum: 240, maximum: 360), spacing: 12, alignment: .leading)]

    /// Zabbix's trigger legend rows: a severity-colored dot and the "Trigger: name [> 90]" label,
    /// listed under the series rows.
    @ViewBuilder
    private var triggerRows: some View {
        ForEach(triggerLines) { line in
            HStack(spacing: 5) {
                Circle()
                    .fill(Color(hex: line.colorHex) ?? .orange)
                    .frame(width: 8, height: 8)
                Text(line.label)
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundStyle(DashboardTheme.secondaryText)
                    .lineLimit(1)
            }
        }
    }

    /// A series' legend stats over the drawn window, formatted with the series' units.
    static func stats(for line: ChartSeries) -> (last: String, min: String, avg: String, max: String)? {
        let values = line.points.compactMap(\.value)
        guard let last = values.last, let minValue = values.min(), let maxValue = values.max(), !values.isEmpty else { return nil }
        let average = values.reduce(0, +) / Double(values.count)
        let format = { (value: Double) in ZabbixValueFormatting.formatLegendStat(value, units: line.units) }
        return (format(last), format(minValue), format(average), format(maxValue))
    }

    /// The short line-dash color key Zabbix uses (not a dot).
    private func swatch(_ line: ChartSeries) -> some View {
        RoundedRectangle(cornerRadius: 1.5)
            .fill(Color(hex: line.colorHex) ?? DashboardTheme.accent)
            .frame(width: 14, height: 3)
    }

    var body: some View {
        if showStats {
            VStack(alignment: .leading, spacing: 3) {
                statsGrid
                triggerRows
            }
        } else {
            VStack(alignment: .leading, spacing: 3) {
                namesGrid
                triggerRows
            }
        }
    }

    private var statsGrid: some View {
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 2) {
                GridRow {
                    Color.clear.frame(width: 1, height: 1).gridCellUnsizedAxes([.horizontal, .vertical])
                    ForEach(["last", "min", "avg", "max"], id: \.self) { header in
                        Text(header)
                            .font(.system(size: 11, weight: .regular, design: .rounded))
                            .foregroundStyle(DashboardTheme.secondaryText)
                    }
                }

                ForEach(series) { line in
                    GridRow {
                        HStack(spacing: 5) {
                            swatch(line)
                            Text("\(line.name) [avg]")
                                .font(.system(size: 11, weight: .regular, design: .rounded))
                                .foregroundStyle(DashboardTheme.secondaryText)
                                .lineLimit(1)
                        }

                        if let stats = Self.stats(for: line) {
                            // Keyed by position, not value — two equal stats (a flat series' last
                            // and min, say) would collide as ForEach identifiers.
                            ForEach(Array([stats.last, stats.min, stats.avg, stats.max].enumerated()), id: \.offset) { _, value in
                                Text(value)
                                    .font(.system(size: 11, weight: .regular, design: .rounded))
                                    .foregroundStyle(DashboardTheme.primaryText)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }
    }

    private var namesGrid: some View {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
                ForEach(series) { line in
                    HStack(alignment: .top, spacing: 5) {
                        swatch(line)
                            // Nudge the swatch down onto the first line's center when the label wraps.
                            .padding(.top, 4)

                        // Show the full series name, wrapping to as many lines as needed rather than
                        // truncating. Zabbix names differ in different places — the "sent/received"
                        // suffix on interface graphs, but the "Department/Specialists/Maintenance"
                        // middle on others — so any truncation (tail *or* middle) can hide exactly the
                        // part that tells two series apart. Wrapping the full text is the only form that
                        // always keeps them distinguishable.
                        Text(line.name)
                            .font(.system(size: 11, weight: .regular, design: .rounded))
                            .foregroundStyle(DashboardTheme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
    }
}

struct PieChartWidgetContentView: View {
    let slices: [ChartSlice]
    var isDonut: Bool = false
    /// Zabbix's pie legend lists names only unless the widget's "Show value" legend option
    /// (`legend_value`) is on — the QA widget has it off and shows bare labels.
    var legendShowsValue: Bool = false

    private let legendColumns = [GridItem(.adaptive(minimum: 170, maximum: 280), spacing: 12, alignment: .leading)]

    var body: some View {
        if slices.isEmpty {
            Text("No data available")
                .font(.system(size: 16, weight: .regular, design: .rounded))
                .foregroundStyle(DashboardTheme.secondaryText)
        } else {
            // Zabbix's layout: the pie fills the widget, centered, with the color-key legend in a
            // wrapping strip along the bottom. A full pie by default — the doughnut hole only when
            // the widget's draw_type asks for one.
            VStack(spacing: 8) {
                Chart(slices) { slice in
                    SectorMark(angle: .value("Value", slice.value), innerRadius: .ratio(isDonut ? 0.5 : 0))
                        .foregroundStyle(Color(hex: slice.colorHex) ?? DashboardTheme.accent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                LazyVGrid(columns: legendColumns, alignment: .leading, spacing: 4) {
                    ForEach(slices) { slice in
                        HStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(Color(hex: slice.colorHex) ?? DashboardTheme.accent)
                                .frame(width: 14, height: 3)
                            Text(slice.name)
                                .font(.system(size: 12, weight: .regular, design: .rounded))
                                .foregroundStyle(DashboardTheme.secondaryText)
                                .lineLimit(1)

                            if legendShowsValue, let valueLabel = slice.valueLabel {
                                Text(valueLabel)
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .foregroundStyle(DashboardTheme.primaryText)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }
        }
    }
}

/// Custom arc-based gauge, since SwiftUI's native `Gauge` control is unavailable on tvOS.
struct GaugeWidgetContentView: View {
    let reading: GaugeReading

    private var fraction: Double {
        let range = reading.maxValue - reading.minValue
        guard range > 0 else { return 0 }
        return ((reading.value - reading.minValue) / range).clamped(to: 0...1)
    }

    /// The gauge's center text. When the item has a value map, it reads like "Up (1.00)" — the
    /// mapped label with the raw value in parentheses, matching Zabbix's own gauge — otherwise the
    /// plain formatted value.
    private var centerText: String {
        guard let mappedText = reading.mappedText else {
            return ZabbixValueFormatting.formatItemValue(reading.value, units: reading.units, decimalPlaces: reading.decimalPlaces)
        }
        return "\(mappedText) (\(ZabbixValueFormatting.formatItemValue(reading.value, units: "", decimalPlaces: reading.decimalPlaces)))"
    }

    /// Zabbix's gauge value-arc fill when the widget doesn't set one — sampled live from the
    /// frontend's SVG (`.svg-gauge-value-arc-sector`: rgb(105, 128, 141)).
    private static let zabbixValueArcColor = Color(red: 105 / 255, green: 128 / 255, blue: 141 / 255)

    /// The unfilled remainder of the arc (`.svg-gauge-empty-arc-sector`: rgb(56, 56, 56)).
    private static let zabbixEmptyArcColor = Color(red: 56 / 255, green: 56 / 255, blue: 56 / 255)

    /// Zabbix's default needle fill (`.svg-gauge-needle` computed fill: rgb(242, 242, 242)).
    private static let zabbixNeedleColor = Color(red: 242 / 255, green: 242 / 255, blue: 242 / 255)

    var body: some View {
        GeometryReader { geometry in
            // Zabbix's gauge, honoring the widget's "Show" checkboxes (verified against the live
            // edit form + SVG): the value sector filling against the dark track (Value arc), a
            // needle pivoting at the arc center (Needle — off on a fresh widget), min/max labels
            // at the arc ends (Scale), the bold value in the arc's mouth (moved below the base
            // line when the needle occupies it, as Zabbix reflows), and the description below.
            // `angle` opens the sweep to 180° or 270°.
            // The drawn stack spans from the arc's crown (−0.5·d) down to the description
            // (+0.27·d) — 0.77·d tall. Sizing to height/0.8 and shifting the square down by
            // +0.115·d keeps that whole extent inside the card's content box, so a tall gauge can
            // never ride up under the card title or clip its description.
            let diameter = max(min(geometry.size.width, geometry.size.height * 1.18), 40)
            // Arc thicknesses honor the widget's own size knobs, as a percent of the radius
            // ("value_arc_size" default 20, "th_arc_size" default 5).
            let lineWidth = max(diameter / 2 * reading.valueArcSizePercent / 100, 8)
            let thresholdArcWidth = max(diameter / 2 * reading.thresholdArcSizePercent / 100, 3)
            let angle = reading.angleDegrees.clamped(to: 90...359)
            let sweep = angle / 360
            // Rotate so the sweep sits symmetrically over the top: 180° gives the flat-based
            // semicircle, 270° leaves its gap centered at the bottom.
            let arcRotation = 90 + (360 - angle) / 2
            // With the thin threshold arc shown, it takes the outer edge and the value arc moves
            // inward under it (Zabbix's stacking), separated by a hair of background.
            let showThresholdArc = reading.showThresholdArc && !reading.thresholds.isEmpty
            let valueArcInset = showThresholdArc ? thresholdArcWidth + diameter * 0.015 : 0

            ZStack {
                if showThresholdArc {
                    // Colored segments from each threshold to the next (the last runs to max);
                    // the span before the first threshold shows the empty-track color.
                    ForEach(Array(thresholdArcSegments.enumerated()), id: \.offset) { _, segment in
                        Circle()
                            .trim(from: sweep * segment.from, to: sweep * segment.to)
                            .stroke(segment.color, style: StrokeStyle(lineWidth: thresholdArcWidth, lineCap: .butt))
                            .rotationEffect(.degrees(arcRotation))
                    }
                }

                if reading.showValueArc {
                    Circle()
                        .trim(from: 0, to: sweep)
                        .stroke(reading.emptyColorHex.flatMap { Color(hex: $0) } ?? Self.zabbixEmptyArcColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                        .rotationEffect(.degrees(arcRotation))
                        .padding(valueArcInset)

                    Circle()
                        .trim(from: 0, to: sweep * fraction)
                        .stroke(gaugeTint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                        .rotationEffect(.degrees(arcRotation))
                        .padding(valueArcInset)
                }

                if reading.showThresholdLabels {
                    // Each threshold's value labeled at its position just outside the arc.
                    ForEach(Array(reading.thresholds.enumerated()), id: \.offset) { _, threshold in
                        let thresholdFraction = thresholdPosition(threshold.value)
                        // Angle measured like the needle: 0 at the sweep's start, over `angle`°.
                        let degrees = (thresholdFraction - 0.5) * angle - 90
                        let radius = diameter / 2 + diameter * 0.045
                        Text(scaleLabel(threshold.value))
                            .font(.system(size: max(diameter * 0.05, 8), weight: .regular, design: .rounded))
                            .foregroundStyle(DashboardTheme.secondaryText)
                            .offset(
                                x: radius * cos(degrees * .pi / 180),
                                y: radius * sin(degrees * .pi / 180)
                            )
                    }
                }

                if reading.showNeedle {
                    // Zabbix's needle: a rounded pivot base tapering to a point (path sampled from
                    // the live SVG), swinging across the configured sweep.
                    GaugeNeedleShape()
                        .fill(reading.needleColorHex.flatMap { Color(hex: $0) } ?? Self.zabbixNeedleColor)
                        .rotationEffect(.degrees((fraction - 0.5) * angle))
                }

                if reading.showScale {
                    Text(scaleLabel(reading.minValue))
                        .font(.system(size: max(diameter * 0.06, 9), weight: .regular, design: .rounded))
                        .foregroundStyle(DashboardTheme.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .offset(x: -(diameter / 2 - lineWidth / 2) + diameter * 0.02, y: lineWidth)

                    Text(scaleLabel(reading.maxValue))
                        .font(.system(size: max(diameter * 0.06, 9), weight: .regular, design: .rounded))
                        .foregroundStyle(DashboardTheme.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .offset(x: (diameter / 2 - lineWidth / 2) - diameter * 0.02, y: lineWidth)
                }

                if reading.showValue {
                    // In the arc's mouth normally; below the pivot when the needle occupies it.
                    Text(centerText)
                        .font(.system(size: diameter * 0.14, weight: .bold, design: .rounded))
                        .foregroundStyle(reading.valueColorHex.flatMap { Color(hex: $0) } ?? DashboardTheme.primaryText)
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .frame(width: diameter * 0.62)
                        .offset(y: reading.showNeedle ? diameter * 0.09 : -diameter * 0.06)
                }

                if reading.showDescription {
                    Text(reading.name)
                        .font(.system(size: max(diameter * 0.1, 12), weight: .regular, design: .rounded))
                        .foregroundStyle(reading.descriptionColorHex.flatMap { Color(hex: $0) } ?? DashboardTheme.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .frame(width: diameter * 0.9)
                        .offset(y: diameter * 0.22)
                }
            }
            .frame(width: diameter, height: diameter)
            // Center the drawn extent (crown → description), not the geometric square.
            .offset(y: diameter * 0.115)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

    private var gaugeTint: Color {
        if let matchingThreshold = reading.thresholds.last(where: { $0.value <= reading.value }),
           let color = Color(hex: matchingThreshold.colorHex) {
            return color
        }
        if let fixedArcColorHex = reading.fixedArcColorHex, let color = Color(hex: fixedArcColorHex) {
            return color
        }
        return Self.zabbixValueArcColor
    }

    /// Where a value sits along the scale, 0...1.
    private func thresholdPosition(_ value: Double) -> Double {
        let range = reading.maxValue - reading.minValue
        guard range > 0 else { return 0 }
        return ((value - reading.minValue) / range).clamped(to: 0...1)
    }

    /// The threshold arc's colored spans: min→first threshold in the empty-track color, then each
    /// threshold's color through to the next (the last running to max) — Zabbix's own banding.
    private var thresholdArcSegments: [(from: Double, to: Double, color: Color)] {
        let emptyColor = reading.emptyColorHex.flatMap { Color(hex: $0) } ?? Self.zabbixEmptyArcColor
        var segments: [(from: Double, to: Double, color: Color)] = []
        var cursor = 0.0
        for (index, threshold) in reading.thresholds.enumerated() {
            let start = thresholdPosition(threshold.value)
            if start > cursor {
                segments.append((cursor, start, index == 0 ? emptyColor : segments.last?.color ?? emptyColor))
            }
            let end = index + 1 < reading.thresholds.count ? thresholdPosition(reading.thresholds[index + 1].value) : 1
            segments.append((start, end, Color(hex: threshold.colorHex) ?? emptyColor))
            cursor = end
        }
        return segments
    }

    /// A scale (or threshold) label with the widget's own "scale_decimal_places" precision and
    /// "scale_show_units" toggle. Each label scales to its own magnitude the way the frontend's
    /// do — a 0…16 GB gauge reads "0 B" at one end and "15 GB" at the other, not "0 GB".
    private func scaleLabel(_ value: Double) -> String {
        let scale = ZabbixValueFormatting.scale(forMaxMagnitude: value, units: reading.units)
        let number = String(format: "%.\(reading.scaleDecimalPlaces)f", value / scale.divisor)
        let suffix = reading.scaleShowsUnits ? "\(scale.prefix)\(reading.units)" : ""
        return suffix.isEmpty ? number : "\(number) \(suffix)"
    }
}

/// Zabbix's gauge needle, translated from the live frontend's SVG path
/// ("M 0.065 1 A 0.065 0.065 0 0 1 -0.065 1 L 0 0.1 Z" in a unit space where 1 is the gauge
/// radius): a rounded pivot base of radius 6.5% of the gauge radius at the arc center, tapering to
/// a sharp point 90% of the way to the rim. Drawn pointing straight up in its bounding square (the
/// square's center is the pivot); the gauge view rotates it to the value's angle.
private struct GaugeNeedleShape: Shape {
    func path(in rect: CGRect) -> Path {
        let radius = min(rect.width, rect.height) / 2
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let baseRadius = radius * 0.065
        let tip = CGPoint(x: center.x, y: center.y - radius * 0.9)

        var path = Path()
        path.move(to: CGPoint(x: center.x + baseRadius, y: center.y))
        // The rounded pivot: the half-circle bulging away from the tip.
        path.addArc(center: center, radius: baseRadius, startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
        path.addLine(to: tip)
        path.closeSubpath()
        return path
    }
}

/// A pointy-top regular hexagon with softly rounded vertices, matching the hexagon Zabbix's own
/// honeycomb draws (verified against the widget's SVG path: vertex at top/bottom, flat edges left
/// and right, corners rounded by roughly 4% of the width). `rect.height` should be
/// `rect.width * 2/sqrt(3)` for the hexagon to come out regular.
struct PointyTopHexagon: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let cx = rect.midX, cy = rect.midY
        let vertices = [
            CGPoint(x: cx, y: cy - h / 2),         // top vertex
            CGPoint(x: cx + w / 2, y: cy - h / 4), // upper-right
            CGPoint(x: cx + w / 2, y: cy + h / 4), // lower-right
            CGPoint(x: cx, y: cy + h / 2),         // bottom vertex
            CGPoint(x: cx - w / 2, y: cy + h / 4), // lower-left
            CGPoint(x: cx - w / 2, y: cy - h / 4), // upper-left
        ]
        let cornerRadius = w * 0.04

        // For each vertex, the points where its two rounded-corner curves meet the adjacent edges:
        // pulled back from the vertex along each edge by the corner radius.
        func pullback(from vertex: CGPoint, toward other: CGPoint) -> CGPoint {
            let edgeLength = hypot(other.x - vertex.x, other.y - vertex.y)
            guard edgeLength > 0 else { return vertex }
            let t = min(cornerRadius / edgeLength, 0.5)
            return CGPoint(x: vertex.x + (other.x - vertex.x) * t, y: vertex.y + (other.y - vertex.y) * t)
        }

        var path = Path()
        let count = vertices.count
        for index in 0..<count {
            let vertex = vertices[index]
            let previous = vertices[(index + count - 1) % count]
            let next = vertices[(index + 1) % count]
            let entry = pullback(from: vertex, toward: previous)
            let exit = pullback(from: vertex, toward: next)
            if index == 0 {
                path.move(to: entry)
            } else {
                path.addLine(to: entry)
            }
            // Round the vertex: curve from the entry point through the vertex to the exit point.
            path.addQuadCurve(to: exit, control: vertex)
        }
        path.closeSubpath()
        return path
    }
}

struct HoneycombWidgetContentView: View {
    let cells: [HoneycombCell]

    /// A pointy-top hexagon's height as a multiple of its width (`2/sqrt(3)`).
    private static let hexHeightRatio: CGFloat = 1.1547005

    /// Zabbix's default honeycomb cell fill in the dark theme — sampled live from the widget's SVG
    /// (`.svg-honeycomb-cell path` computed fill: rgb(61, 80, 89)).
    private static let zabbixCellFill = Color(red: 61 / 255, green: 80 / 255, blue: 89 / 255)

    /// Zabbix's honeycomb label color (`.svg-honeycomb-label` computed color: rgb(238, 238, 238)).
    private static let zabbixLabelColor = Color(red: 238 / 255, green: 238 / 255, blue: 238 / 255)

    /// The gap between hexagons is proportional to the cell — 1/12 of the hexagon width, matching
    /// the frontend's cells_gap (cell_width / 12 in its fixed 1000-unit cell space).
    static func hexGap(forHexWidth hexWidth: CGFloat) -> CGFloat { hexWidth / 12 }

    /// The frontend hides labels entirely once a rendered cell is narrower than 56 px
    /// (LABEL_WIDTH_MIN) — below that nothing legible fits anyway.
    private static let labelMinCellWidth: CGFloat = 56

    /// The frontend never renders a label below 12 on-screen pixels (FONT_SIZE_MIN).
    private static let labelMinFontSize: CGFloat = 12

    /// Picks the pointy-top honeycomb packing for `count` hexagons in `size`, replicating the
    /// frontend's algorithm (read from Zabbix 7.0's honeycomb widget as a behavior spec, and
    /// verified against two live widgets: 208 cells in 1682×1077 → 17 columns × 13 rows; 56 cells
    /// in a full-page widget → 11 × 6): estimate rows as sqrt(height·count/width), evaluate the
    /// floor and ceil row counts by the scale each achieves (columns = ⌊count/rows⌋, rows
    /// recomputed as ⌈count/columns⌉, width spanning columns plus a half-cell stagger when a second
    /// row exists and is at least half full), and keep whichever scales larger — the ceil candidate
    /// on an exact tie. Returns the chosen columns/rows and the hexagon width (gap included).
    static func honeycombLayout(count: Int, size: CGSize) -> (columns: Int, rows: Int, hexWidth: CGFloat) {
        guard count > 0, size.width > 0, size.height > 0 else { return (max(count, 1), 1, max(size.width, 0)) }

        // The frontend lays out in a fixed cell space (width 1000, height 2/√3·1000, gap 1000/12)
        // and scales the whole honeycomb to fit; the ratios are what matter.
        let cellW: CGFloat = 1000
        let cellH: CGFloat = 1000 * hexHeightRatio
        let gap = cellW / 12

        func candidate(_ rowsEstimate: Int) -> (columns: Int, rows: Int, scale: CGFloat) {
            let columns = max(1, count / max(rowsEstimate, 1))
            let rows = Int((Double(count) / Double(columns)).rounded(.up))
            let widthUnits = cellW * CGFloat(columns) + (rows > 1 && columns * 2 <= count ? cellW / 2 : 0)
            let heightUnits = cellH * 0.25 * CGFloat(3 * rows + 1) - gap
            let scale = min(size.width / (widthUnits - gap * 0.5), size.height / heightUnits)
            return (columns, rows, scale)
        }

        let estimate = max(1, min(Double(count), (Double(size.height) * Double(count) / Double(size.width)).squareRoot()))
        let lower = candidate(Int(estimate.rounded(.down)))
        let upper = candidate(Int(estimate.rounded(.up)))
        let best = lower.scale > upper.scale ? lower : upper
        return (best.columns, best.rows, cellW * best.scale)
    }

    /// Per-cell label font sizes, replicating the frontend's auto sizing: each label is sized so
    /// its text spans ~78.75% of the label area's width (measured at a 10 pt reference and scaled),
    /// labels are then bucketed by text length rounded up to multiples of 8 with each bucket
    /// sharing its smallest size (so similar-length labels render uniformly instead of raggedly),
    /// capped by the label area height, floored at 12 pt, and — when primary + secondary together
    /// overflow the area — both are scaled down proportionally. Cells narrower than 56 pt hide
    /// labels entirely. Overflowing text is ellipsized, never shrunk per cell.
    static func honeycombLabelFonts(
        cells: [HoneycombCell],
        hexWidth: CGFloat,
        measure: (String, Bool) -> CGFloat = { Self.measuredLabelWidth($0, bold: $1) }
    ) -> [(primary: CGFloat, secondary: CGFloat)] {
        let gap = hexGap(forHexWidth: hexWidth)
        guard hexWidth - gap >= labelMinCellWidth else {
            return Array(repeating: (0, 0), count: cells.count)
        }

        let fitWidth = hexWidth - gap * 1.25 - 8
        // The label block occupies cellHeight/2.25 of the cell; dividing by the 1.15 line height
        // converts that to a font-size budget, like the frontend does.
        let areaHeight = hexWidth * Self.hexHeightRatio / 2.25 / 1.15

        func fonts(_ texts: [String], bold: Bool) -> [CGFloat] {
            var sizes = texts.map { text -> CGFloat in
                guard !text.isEmpty else { return 0 }
                let width = measure(text, bold)
                guard width > 0 else { return 0 }
                return max(Self.labelMinFontSize, fitWidth * 0.875 / width * 9)
            }
            var bucketMin: [Int: CGFloat] = [:]
            for (index, text) in texts.enumerated() where !text.isEmpty {
                let bucket = Int((Double(text.count) / 8).rounded(.up)) * 8
                bucketMin[bucket] = min(bucketMin[bucket] ?? .infinity, sizes[index])
            }
            for (index, text) in texts.enumerated() where !text.isEmpty {
                let bucket = Int((Double(text.count) / 8).rounded(.up)) * 8
                sizes[index] = max(
                    Self.labelMinFontSize,
                    min(bucketMin[bucket] ?? sizes[index], areaHeight.rounded(.down))
                )
            }
            return sizes
        }

        let primary = fonts(cells.map(\.primaryLabel), bold: false)
        let secondary = fonts(cells.map(\.secondaryLabel), bold: true)

        return zip(primary, secondary).map { p, s in
            if p + s > areaHeight, p + s > 0 {
                let scale = areaHeight / (p + s)
                return (p > 0 ? max(Self.labelMinFontSize, p * scale) : 0,
                        s > 0 ? max(Self.labelMinFontSize, s * scale) : 0)
            }
            return (p, s)
        }
    }

    /// Width of `text` at the 10 pt reference size in the fonts the cells render with.
    static func measuredLabelWidth(_ text: String, bold: Bool) -> CGFloat {
        let base = UIFont.systemFont(ofSize: 10, weight: bold ? .bold : .regular)
        let font = base.fontDescriptor.withDesign(.rounded).map { UIFont(descriptor: $0, size: 10) } ?? base
        return (text as NSString).size(withAttributes: [.font: font]).width
    }

    var body: some View {
        if cells.isEmpty {
            Text("No items match this widget's filters")
                .font(.system(size: 16, weight: .regular, design: .rounded))
                .foregroundStyle(DashboardTheme.secondaryText)
        } else {
            GeometryReader { geometry in
                let layout = Self.honeycombLayout(count: cells.count, size: geometry.size)
                let hexWidth = layout.hexWidth
                let hexHeight = hexWidth * Self.hexHeightRatio
                // A second row shifts right half a cell only when it is at least half full — the
                // frontend's stagger condition, which also widens the honeycomb's extent.
                let rowShift: CGFloat = layout.rows > 1 && layout.columns * 2 <= cells.count ? 0.5 : 0
                // The honeycomb's own extent, so the cluster centers in the widget like Zabbix's.
                let usedWidth = hexWidth * (CGFloat(layout.columns) + rowShift)
                let usedHeight = hexHeight * (0.75 * CGFloat(layout.rows) + 0.25)
                let originX = (geometry.size.width - usedWidth) / 2
                let originY = (geometry.size.height - usedHeight) / 2
                let fonts = Self.honeycombLabelFonts(cells: cells, hexWidth: hexWidth)

                ZStack(alignment: .topLeading) {
                    ForEach(Array(cells.enumerated()), id: \.element.id) { index, cell in
                        let column = index % layout.columns
                        let row = index / layout.columns
                        let centerX = originX + hexWidth / 2 + CGFloat(column) * hexWidth
                            + (row % 2 == 1 ? hexWidth / 2 : 0)
                        let centerY = originY + hexHeight / 2 + CGFloat(row) * 0.75 * hexHeight
                        hexCell(
                            cell,
                            width: hexWidth,
                            height: hexHeight,
                            fonts: index < fonts.count ? fonts[index] : (0, 0)
                        )
                        .position(x: centerX, y: centerY)
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
            }
        }
    }

    /// One hexagon cell, matching Zabbix's: labels at the widget-wide auto-computed sizes (short
    /// labels like extension numbers come out large, long ones uniform and ellipsized — never
    /// shrunk per cell), near-white and centered on the slate cell fill (threshold coloring
    /// overrides the fill). A label whose size resolved to 0 — hidden by the Show checkbox, empty,
    /// or a cell too small for legible text — is omitted so the rest centers.
    private func hexCell(
        _ cell: HoneycombCell,
        width: CGFloat,
        height: CGFloat,
        fonts: (primary: CGFloat, secondary: CGFloat)
    ) -> some View {
        let gap = Self.hexGap(forHexWidth: width)
        let fitWidth = width - gap * 1.25 - 8
        return VStack(spacing: 0) {
            if !cell.primaryLabel.isEmpty, fonts.primary > 0 {
                Text(cell.primaryLabel)
                    .font(.system(size: fonts.primary, weight: .regular, design: .rounded))
                    .foregroundStyle(Self.zabbixLabelColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            if !cell.secondaryLabel.isEmpty, fonts.secondary > 0 {
                Text(cell.secondaryLabel)
                    .font(.system(size: fonts.secondary, weight: .bold, design: .rounded))
                    .foregroundStyle(Self.zabbixLabelColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .frame(maxWidth: max(fitWidth, 0))
        .frame(width: width - gap, height: height - gap)
        .background(
            PointyTopHexagon()
                .fill(cell.backgroundColorHex.flatMap { Color(hex: $0) } ?? Self.zabbixCellFill)
        )
        .clipShape(PointyTopHexagon())
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
            // Zabbix centers every Top hosts column — the header and its values sit centered in
            // the column's width (verified against the live widget), not flushed left.
            AutoScrollingContent {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        ForEach(Array(columns.enumerated()), id: \.offset) { _, title in
                            Text(title)
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(DashboardTheme.secondaryText)
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                    }

                    ForEach(rows) { row in
                        HStack {
                            ForEach(Array(row.values.enumerated()), id: \.offset) { index, value in
                                // A column's threshold band (or its static base color) paints the
                                // whole cell background, exactly like the frontend's table.
                                let cellColor = row.cellColors.indices.contains(index) ? row.cellColors[index].flatMap { Color(hex: $0) } : nil
                                Text(value)
                                    .font(.system(size: 16, weight: .medium, design: .rounded))
                                    .foregroundStyle(DashboardTheme.primaryText)
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .padding(.vertical, 2)
                                    .background(cellColor ?? .clear)
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
    /// True when the fetch hit its limit — Zabbix appends its standard truncation note.
    var truncated: Bool = false

    /// The steel blue of Zabbix's dependency arrow inside a trigger cell.
    private static let dependencyIconColor = Color(hex: "6E8FBF") ?? .blue

    /// One column per distinct trigger name — Zabbix's trigger overview is a host × trigger matrix,
    /// not a per-host strip of chips.
    private static let triggerColumnWidth: CGFloat = 64
    private static let rotatedHeaderHeight: CGFloat = 130
    private static let cellHeight: CGFloat = 27

    /// Distinct trigger names across all hosts, in first-appearance order: the matrix's columns.
    private var triggerColumns: [String] {
        var seen = Set<String>()
        var columns: [String] = []
        for row in rows {
            for trigger in row.triggers where !seen.contains(trigger.name) {
                seen.insert(trigger.name)
                columns.append(trigger.name)
            }
        }
        return columns
    }

    var body: some View {
        if rows.isEmpty {
            Text("No active triggers")
                .font(.system(size: 16, weight: .regular, design: .rounded))
                .foregroundStyle(DashboardTheme.secondaryText)
        } else {
            let columns = triggerColumns
            // Zabbix's layout: a "Hosts" column of host names, one column per trigger with its name
            // rotated vertically in the header, and a full severity-colored cell where that host has
            // that trigger in problem state (green when an OK trigger is shown via "Show: Any");
            // blank where the host doesn't have the trigger.
            AutoScrollingContent {
                VStack(alignment: .leading, spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    Grid(alignment: .leading, horizontalSpacing: 3, verticalSpacing: 3) {
                        GridRow {
                            Text("Hosts")
                                .font(.system(size: 14, weight: .regular, design: .rounded))
                                .foregroundStyle(DashboardTheme.secondaryText)
                                .frame(maxHeight: .infinity, alignment: .bottom)
                                .gridColumnAlignment(.leading)

                            ForEach(columns, id: \.self) { name in
                                // Rotated header: lay the text out horizontally at the header's
                                // height, then rotate it into the narrow column.
                                Text(name)
                                    .font(.system(size: 12, weight: .regular, design: .rounded))
                                    .foregroundStyle(DashboardTheme.secondaryText)
                                    .lineLimit(1)
                                    .frame(width: Self.rotatedHeaderHeight - 10, alignment: .leading)
                                    .rotationEffect(.degrees(-90))
                                    .frame(width: Self.triggerColumnWidth, height: Self.rotatedHeaderHeight, alignment: .bottom)
                            }
                        }

                        ForEach(rows) { row in
                            GridRow {
                                Text(row.hostName)
                                    .font(.system(size: 15, weight: .regular, design: .rounded))
                                    .foregroundStyle(DashboardTheme.primaryText)
                                    .lineLimit(1)
                                    .frame(minWidth: 150, alignment: .leading)

                                ForEach(columns, id: \.self) { name in
                                    if let trigger = row.triggers.first(where: { $0.name == name }) {
                                        // A dependent trigger carries Zabbix's small arrow icon
                                        // at the cell's leading edge.
                                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                                            .fill(trigger.isProblem ? severityIndicatorColor(for: trigger.severity) : Color.green)
                                            .frame(width: Self.triggerColumnWidth, height: Self.cellHeight)
                                            .overlay(alignment: .leading) {
                                                if trigger.hasDependency {
                                                    Image(systemName: "arrow.up")
                                                        .font(.system(size: 12, weight: .bold))
                                                        .foregroundStyle(Self.dependencyIconColor)
                                                        .padding(.leading, 6)
                                                }
                                            }
                                    } else {
                                        Color.clear
                                            .frame(width: Self.triggerColumnWidth, height: Self.cellHeight)
                                    }
                                }
                            }
                        }
                    }
                }

                // Zabbix's standard note when the underlying query was cut off at its limit.
                if truncated {
                    Text("Not all results are displayed. Please provide more specific search criteria.")
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .foregroundStyle(DashboardTheme.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 6)
                }
                }
            }
        }
    }
}

struct ProblemHostsWidgetContentView: View {
    let summaries: [HostGroupProblemSummary]

    /// Severity columns left→right from Disaster (5) down to Not classified (0), matching Zabbix's
    /// per-group problems table.
    private static let severityColumns = Array((0...5).reversed())

    private static let countColumnWidth: CGFloat = 78

    var body: some View {
        if summaries.isEmpty {
            Text("No host groups with active problems")
                .font(.system(size: 16, weight: .regular, design: .rounded))
                .foregroundStyle(DashboardTheme.secondaryText)
        } else {
            // Zabbix's table: a "Host group" column of names, one column per severity, and a colored
            // count cell only where that group has problems at that severity — blank otherwise.
            AutoScrollingContent {
                Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 6) {
                    GridRow {
                        Text("Host group")
                            .font(.system(size: 14, weight: .regular, design: .rounded))
                            .foregroundStyle(DashboardTheme.secondaryText)
                            .gridColumnAlignment(.leading)

                        ForEach(Self.severityColumns, id: \.self) { severity in
                            Text(SeverityPalette.name(for: severity))
                                .font(.system(size: 14, weight: .regular, design: .rounded))
                                .foregroundStyle(DashboardTheme.secondaryText)
                                .lineLimit(1)
                                .frame(width: Self.countColumnWidth, alignment: .leading)
                        }
                    }

                    ForEach(summaries) { summary in
                        GridRow {
                            // Group names are hyperlinks in the frontend — the same link blue
                            // here, since visual parity is the point even where tvOS can't follow
                            // the link.
                            Text(summary.groupName)
                                .font(.system(size: 16, weight: .medium, design: .rounded))
                                .foregroundStyle(Color(hex: "4796C4") ?? DashboardTheme.primaryText)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            ForEach(Self.severityColumns, id: \.self) { severity in
                                let count = summary.countsBySeverity.indices.contains(severity) ? summary.countsBySeverity[severity] : 0
                                Group {
                                    if count > 0 {
                                        Text("\(count)")
                                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                                            .foregroundStyle(.black.opacity(0.87))
                                            .padding(.horizontal, 6)
                                            .frame(width: Self.countColumnWidth, height: 26, alignment: .leading)
                                            .background(
                                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                                    .fill(severityIndicatorColor(for: severity))
                                            )
                                    } else {
                                        Color.clear.frame(width: Self.countColumnWidth, height: 26)
                                    }
                                }
                            }
                        }
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
            AutoScrollingContent {
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

    private func statusColor(for status: WebScenarioStatus) -> Color {
        switch status {
        case .ok: .green
        case .failed: .red
        case .unknown: .gray
        }
    }

    private func statusLabel(for status: WebScenarioStatus) -> String {
        switch status {
        case .ok: "Ok"
        case .failed: "Failed"
        case .unknown: "Unknown"
        }
    }

    var body: some View {
        if scenarios.isEmpty {
            Text("No web scenarios configured")
                .font(.system(size: 16, weight: .regular, design: .rounded))
                .foregroundStyle(DashboardTheme.secondaryText)
        } else {
            AutoScrollingContent {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(scenarios.prefix(15)) { scenario in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(statusColor(for: scenario.status))
                                .frame(width: 10, height: 10)

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

                            Spacer(minLength: 4)

                            Text(statusLabel(for: scenario.status))
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(statusColor(for: scenario.status))
                        }
                    }
                }
            }
        }
    }
}

struct ItemHistoryWidgetContentView: View {
    let series: [ItemHistorySeries]
    var showTimestamp: Bool = false

    /// One rendered row: a reading tagged with its column's display name. Zabbix lists readings as
    /// "Name | Value" rows (newest first, interleaved across columns by time), not per-item
    /// sections — verified against the live widget, which repeats "Memory" on every row.
    private struct Row: Identifiable {
        let id: String
        let name: String
        let value: String
        let date: Date
        let colorHex: String?
    }

    private var rows: [Row] {
        series
            .flatMap { line in line.values.map { Row(id: $0.id, name: line.itemName, value: $0.value, date: $0.date, colorHex: $0.colorHex) } }
            .sorted { $0.date > $1.date }
    }

    var body: some View {
        AutoScrollingContent {
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 5) {
                ForEach(rows) { row in
                    GridRow {
                        Text(row.name)
                            .font(.system(size: 15, weight: .regular, design: .rounded))
                            .foregroundStyle(DashboardTheme.secondaryText)
                            .lineLimit(1)

                        // The column's threshold band (or base color) paints the value cell,
                        // as the frontend does.
                        Text(row.value)
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundStyle(DashboardTheme.primaryText)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 1)
                            .background(row.colorHex.flatMap { Color(hex: $0) } ?? .clear)

                        // The timestamp column only when the widget's show_timestamp asks for it —
                        // Zabbix's default hides it.
                        if showTimestamp {
                            Text(row.date, style: .time)
                                .font(.system(size: 13, weight: .regular, design: .rounded))
                                .foregroundStyle(DashboardTheme.secondaryText)
                        }
                    }
                }
            }
        }
    }
}

struct DataOverviewWidgetContentView: View {
    let matrix: DataOverviewMatrix

    private let headerWidth: CGFloat = 130
    private let cellWidth: CGFloat = 74

    /// Column headers rotate vertically, as Zabbix's data overview draws them — a horizontal
    /// truncation at 74pt left most item names unreadable ("Interface e...").
    private static let rotatedHeaderHeight: CGFloat = 120

    var body: some View {
        if matrix.rows.isEmpty {
            Text("No items match this widget's filters")
                .font(.system(size: 16, weight: .regular, design: .rounded))
                .foregroundStyle(DashboardTheme.secondaryText)
        } else {
            // A hosts×items grid; scrolls horizontally when there are more columns than fit and
            // vertically (auto) through the rows.
            AutoScrollingContent {
                ScrollView(.horizontal, showsIndicators: false) {
                    Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 4) {
                        GridRow {
                            Color.clear.frame(width: headerWidth, height: 1) // corner spacer
                            ForEach(Array(matrix.columnHeaders.enumerated()), id: \.offset) { _, header in
                                // Lay the text out horizontally at the header's height, then rotate
                                // it into the narrow column (the same rotated-header treatment as
                                // the trigger overview matrix).
                                Text(header)
                                    .font(.system(size: 12, weight: .regular, design: .rounded))
                                    .foregroundStyle(DashboardTheme.secondaryText)
                                    .lineLimit(1)
                                    .frame(width: Self.rotatedHeaderHeight - 8, alignment: .leading)
                                    .rotationEffect(.degrees(-90))
                                    .frame(width: cellWidth, height: Self.rotatedHeaderHeight, alignment: .bottom)
                            }
                        }

                        ForEach(matrix.rows) { row in
                            GridRow {
                                Text(row.header)
                                    .font(.system(size: 14, weight: .medium, design: .rounded))
                                    .foregroundStyle(DashboardTheme.primaryText)
                                    .lineLimit(1)
                                    .frame(width: headerWidth, alignment: .leading)

                                // Zabbix draws data-overview values in the plain foreground color,
                                // not link-blue.
                                ForEach(Array(row.cells.enumerated()), id: \.offset) { _, cell in
                                    Text(cell)
                                        .font(.system(size: 14, weight: .regular, design: .rounded))
                                        .foregroundStyle(DashboardTheme.primaryText)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.7)
                                        .frame(width: cellWidth, alignment: .leading)
                                }
                            }
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

