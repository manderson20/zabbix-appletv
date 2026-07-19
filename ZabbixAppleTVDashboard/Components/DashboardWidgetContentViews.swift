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
        if diagram.elements.isEmpty {
            Text("This map has no elements")
                .font(.system(size: 16, weight: .regular, design: .rounded))
                .foregroundStyle(DashboardTheme.secondaryText)
        } else {
            GeometryReader { geometry in
                let scaleX = geometry.size.width / CGFloat(max(diagram.width, 1))
                let scaleY = geometry.size.height / CGFloat(max(diagram.height, 1))

                ZStack(alignment: .topLeading) {
                    if let backgroundImage {
                        Image(uiImage: backgroundImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .clipped()
                    }

                    Canvas { context, _ in
                        for link in diagram.links {
                            var path = Path()
                            path.move(to: CGPoint(x: CGFloat(link.fromX) * scaleX, y: CGFloat(link.fromY) * scaleY))
                            path.addLine(to: CGPoint(x: CGFloat(link.toX) * scaleX, y: CGFloat(link.toY) * scaleY))
                            context.stroke(path, with: .color(Color(hex: link.colorHex) ?? .gray), lineWidth: 2)
                        }
                    }

                    ForEach(diagram.elements) { element in
                        VStack(spacing: 2) {
                            NetworkMapElementIconView(element: element)
                            Text(element.label)
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(DashboardTheme.primaryText)
                                .lineLimit(1)
                                .fixedSize()
                        }
                        .position(x: CGFloat(element.x) * scaleX, y: CGFloat(element.y) * scaleY)
                    }
                }
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
        let values = series.flatMap(\.points).compactMap(\.value)
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

    private var segmentedChart: some View {
        let segments = segments
        return Chart {
            ForEach(segments) { segment in
                ForEach(segment.points) { point in
                    marks(for: point, in: segment)
                }
            }
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
        }
        .chartForegroundStyleScale(
            domain: series.map(\.id),
            range: series.map { Color(hex: $0.colorHex) ?? DashboardTheme.accent }
        )
    }

    /// Axis/legend configuration shared by the stacked and non-stacked charts.
    private func styled(_ chart: some View) -> some View {
        chart
            // Swift Charts' built-in legend doesn't wrap long labels within the card's actual width,
            // so it's hidden in favor of the wrapping `ChartLegendView` below.
            .chartLegend(.hidden)
            // Pin the x-axis to the widget's full configured window rather than auto-fitting to the
            // data, so a period with no data reads as blank space at the right spot.
            .chartXScale(domain: window.start...window.end)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 3)) {
                    AxisValueLabel(format: .dateTime.hour().minute())
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                }
            }
            .chartYAxis {
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
            // Pin the Y-axis to the widget's configured lefty_min/lefty_max when set; otherwise
            // Swift Charts auto-scales to the data.
            .chartYScaleIfSet(yScaleDomain)
    }

    var body: some View {
        if series.allSatisfy({ $0.points.isEmpty }) {
            Text("No data for this time period")
                .font(.system(size: 16, weight: .regular, design: .rounded))
                .foregroundStyle(DashboardTheme.secondaryText)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                if stacked {
                    styled(stackedChart)
                } else {
                    styled(segmentedChart)
                }

                // Zabbix shows the legend whenever it's enabled — including single-series graphs,
                // where the color key is what names the series ("— BSD-DNS1: Available memory").
                if showLegend {
                    ChartLegendView(series: series, showStats: showLegendStats)
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

    private let columns = [GridItem(.adaptive(minimum: 240, maximum: 360), spacing: 12, alignment: .leading)]

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
        } else {
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
}

struct PieChartWidgetContentView: View {
    let slices: [ChartSlice]
    var isDonut: Bool = false

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

                            if let valueLabel = slice.valueLabel {
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

    var body: some View {
        GeometryReader { geometry in
            // Zabbix's gauge is a thick filled arc, no needle: the value sector fills clockwise
            // against a dark track, the bold value sits in the arc's mouth, the min/max labels sit
            // at the arc's ends, and the description below in large text — all verified against the
            // live frontend's SVG structure (value/empty arc sectors, left/right labels,
            // value-and-units, description).
            // Capped so the arc + value + description stack (which extends ~0.28·d below the arc's
            // flat edge) still fits the card height without clipping the description.
            let diameter = max(min(geometry.size.width, geometry.size.height * 1.15), 40)
            let lineWidth = max(diameter * 0.13, 8)

            ZStack {
                Circle()
                    .trim(from: 0, to: 0.5)
                    .stroke(Self.zabbixEmptyArcColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                    .rotationEffect(.degrees(180))

                Circle()
                    .trim(from: 0, to: 0.5 * fraction)
                    .stroke(gaugeTint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                    .rotationEffect(.degrees(180))

                Text(ZabbixValueFormatting.format(reading.minValue, units: reading.units))
                    .font(.system(size: max(diameter * 0.06, 9), weight: .regular, design: .rounded))
                    .foregroundStyle(DashboardTheme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .offset(x: -(diameter / 2 - lineWidth / 2) + diameter * 0.02, y: lineWidth)

                Text(ZabbixValueFormatting.format(reading.maxValue, units: reading.units))
                    .font(.system(size: max(diameter * 0.06, 9), weight: .regular, design: .rounded))
                    .foregroundStyle(DashboardTheme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .offset(x: (diameter / 2 - lineWidth / 2) - diameter * 0.02, y: lineWidth)

                // The value in the arc's mouth — the open space under the arc's crown.
                Text(centerText)
                    .font(.system(size: diameter * 0.14, weight: .bold, design: .rounded))
                    .foregroundStyle(DashboardTheme.primaryText)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .frame(width: diameter * 0.62)
                    .offset(y: -diameter * 0.06)

                Text(reading.name)
                    .font(.system(size: max(diameter * 0.1, 12), weight: .regular, design: .rounded))
                    .foregroundStyle(DashboardTheme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(width: diameter * 0.9)
                    .offset(y: diameter * 0.22)
            }
            .frame(width: diameter, height: diameter)
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
}

/// A flat-top regular hexagon inscribed in its rect: flat edges top and bottom, points left and
/// right. `rect.height` should be `rect.width * sqrt(3)/2` for the hexagon to come out regular.
struct FlatTopHexagon: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let cx = rect.midX, cy = rect.midY
        let points = [
            CGPoint(x: cx + w / 2, y: cy),        // right vertex
            CGPoint(x: cx + w / 4, y: cy - h / 2), // top-right
            CGPoint(x: cx - w / 4, y: cy - h / 2), // top-left
            CGPoint(x: cx - w / 2, y: cy),        // left vertex
            CGPoint(x: cx - w / 4, y: cy + h / 2), // bottom-left
            CGPoint(x: cx + w / 4, y: cy + h / 2), // bottom-right
        ]
        var path = Path()
        path.addLines(points)
        path.closeSubpath()
        return path
    }
}

struct HoneycombWidgetContentView: View {
    let cells: [HoneycombCell]

    /// A flat-top hexagon's height as a fraction of its width (`sqrt(3)/2`).
    private static let hexHeightRatio: CGFloat = 0.8660254

    /// Thin gap between hexagons, so cells read as separate tiles (as Zabbix draws them) rather than
    /// one continuous mesh.
    private static let hexGap: CGFloat = 4

    /// Picks the flat-top honeycomb packing that fills `size` with `count` hexagons at the largest
    /// size that still fits — so a few items become a few big hexagons and many stay legible. Flat-top
    /// hexagons tessellate in offset columns: columns advance by 3/4 of a hexagon's width, and every
    /// other column is dropped half a hexagon's height, so the used height spans `rows + 0.5`. For
    /// each candidate column count the hexagon size is capped by both width and height; the count that
    /// yields the biggest hexagon wins. Returns the chosen columns/rows and that hexagon width.
    static func honeycombLayout(count: Int, size: CGSize) -> (columns: Int, rows: Int, hexWidth: CGFloat) {
        guard count > 0, size.width > 0, size.height > 0 else { return (max(count, 1), 1, max(size.width, 0)) }

        var best = (columns: 1, rows: count, hexWidth: CGFloat(0))
        for columns in 1...count {
            let rows = Int((Double(count) / Double(columns)).rounded(.up))
            let columnOffset: CGFloat = columns > 1 ? 0.5 : 0 // alternating columns drop half a hex
            let widthLimited = size.width / (0.75 * CGFloat(columns - 1) + 1)
            let heightLimited = size.height / (hexHeightRatio * (CGFloat(rows) + columnOffset))
            let hexWidth = min(widthLimited, heightLimited)
            if hexWidth > best.hexWidth {
                best = (columns, rows, hexWidth)
            }
        }
        return best
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
                let columnOffset: CGFloat = layout.columns > 1 ? 0.5 : 0
                // The honeycomb's own extent, so it can be centered in whatever space is left over.
                let usedWidth = hexWidth * (0.75 * CGFloat(layout.columns - 1) + 1)
                let usedHeight = hexHeight * (CGFloat(layout.rows) + columnOffset)
                let originX = (geometry.size.width - usedWidth) / 2
                let originY = (geometry.size.height - usedHeight) / 2

                ZStack(alignment: .topLeading) {
                    ForEach(Array(cells.enumerated()), id: \.element.id) { index, cell in
                        let column = index % layout.columns
                        let row = index / layout.columns
                        let centerX = originX + hexWidth / 2 + CGFloat(column) * 0.75 * hexWidth
                        let centerY = originY + hexHeight / 2 + CGFloat(row) * hexHeight
                            + (column % 2 == 1 ? hexHeight / 2 : 0)
                        hexCell(cell, width: hexWidth, height: hexHeight)
                            .position(x: centerX, y: centerY)
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
            }
        }
    }

    /// One hexagon cell, its fill clipped to the hexagon and its label/value scaled to the cell so a
    /// few large hexagons read from across the room and many small ones still fit. Text is inset
    /// horizontally so it stays clear of the hexagon's slanted top/bottom edges.
    private func hexCell(_ cell: HoneycombCell, width: CGFloat, height: CGFloat) -> some View {
        VStack(spacing: 2) {
            Text(cell.primaryLabel)
                .font(.system(size: min(max(height * 0.17, 11), 32), weight: .bold, design: .rounded))
                .foregroundStyle(DashboardTheme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.5)

            Text(cell.secondaryLabel)
                .font(.system(size: min(max(height * 0.14, 9), 24), weight: .regular, design: .rounded))
                .foregroundStyle(DashboardTheme.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
        .padding(.horizontal, width * 0.16)
        .frame(width: width - Self.hexGap, height: height - Self.hexGap)
        .background(
            FlatTopHexagon()
                .fill(cell.backgroundColorHex.flatMap { Color(hex: $0) } ?? DashboardTheme.secondaryCardBackground)
        )
        .clipShape(FlatTopHexagon())
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
            AutoScrollingContent {
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
                                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                                            .fill(trigger.isProblem ? severityIndicatorColor(for: trigger.severity) : Color.green)
                                            .frame(width: Self.triggerColumnWidth, height: Self.cellHeight)
                                    } else {
                                        Color.clear
                                            .frame(width: Self.triggerColumnWidth, height: Self.cellHeight)
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
                            Text(summary.groupName)
                                .font(.system(size: 16, weight: .medium, design: .rounded))
                                .foregroundStyle(DashboardTheme.primaryText)
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
    }

    private var rows: [Row] {
        series
            .flatMap { line in line.values.map { Row(id: $0.id, name: line.itemName, value: $0.value, date: $0.date) } }
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

                        Text(row.value)
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundStyle(DashboardTheme.primaryText)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)

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
                                Text(header)
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .foregroundStyle(DashboardTheme.secondaryText)
                                    .lineLimit(1)
                                    .frame(width: cellWidth, alignment: .leading)
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

