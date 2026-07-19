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

    private var units: String { series.first?.units ?? "" }

    private var yAxisScale: ZabbixValueFormatting.Scale {
        let maxValue = series.flatMap(\.points).compactMap(\.value).max() ?? 0
        return ZabbixValueFormatting.scale(forMaxMagnitude: maxValue, units: units)
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
        // own value. Pinning yStart to 0 draws each series' fill independently from the bottom.
        // `point.value` is non-nil within a segment by construction.
        AreaMark(x: .value("Time", point.date), yStart: .value("Baseline", 0), yEnd: .value(segment.seriesName, point.value ?? 0))
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

                if showLegend, series.count > 1 {
                    ChartLegendView(series: series)
                }
            }
        }
    }
}

/// A wrapping legend for `LineChartWidgetContentView`, since Swift Charts' built-in legend can
/// run long labels (full Zabbix item names) off the edge of the card instead of wrapping them.
private struct ChartLegendView: View {
    let series: [ChartSeries]

    private let columns = [GridItem(.adaptive(minimum: 240, maximum: 360), spacing: 12, alignment: .leading)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
            ForEach(series) { line in
                HStack(alignment: .top, spacing: 5) {
                    Circle()
                        .fill(Color(hex: line.colorHex) ?? DashboardTheme.accent)
                        .frame(width: 8, height: 8)
                        // Nudge the swatch down onto the first line's center when the label wraps.
                        .padding(.top, 3)

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

    var body: some View {
        if slices.isEmpty {
            Text("No data available")
                .font(.system(size: 16, weight: .regular, design: .rounded))
                .foregroundStyle(DashboardTheme.secondaryText)
        } else {
            HStack(spacing: 12) {
                Chart(slices) { slice in
                    SectorMark(angle: .value("Value", slice.value), innerRadius: .ratio(0.5))
                        .foregroundStyle(Color(hex: slice.colorHex) ?? DashboardTheme.accent)
                }
                .frame(maxWidth: 110)

                VStack(alignment: .leading, spacing: 4) {
                    ForEach(slices.prefix(6)) { slice in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color(hex: slice.colorHex) ?? DashboardTheme.accent)
                                .frame(width: 10, height: 10)
                            Text(slice.name)
                                .font(.system(size: 13, weight: .regular, design: .rounded))
                                .foregroundStyle(DashboardTheme.secondaryText)
                                .lineLimit(1)

                            if let valueLabel = slice.valueLabel {
                                Spacer(minLength: 4)
                                Text(valueLabel)
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
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

    var body: some View {
        GeometryReader { geometry in
            // A 180° semicircle sweeping from the minimum on the left, over the top, to the maximum
            // on the right — plus a needle pointing at the current value — matching Zabbix's own
            // gauge widget rather than a bare arc. The flat side faces down, so the lower half of
            // the bounding square holds the value, item name, and the min/max end labels.
            let diameter = max(min(geometry.size.width, geometry.size.height), 40)
            let lineWidth = max(diameter * 0.09, 6)

            ZStack {
                Circle()
                    .trim(from: 0, to: 0.5)
                    .stroke(DashboardTheme.secondaryCardBackground, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(180))

                Circle()
                    .trim(from: 0, to: 0.5 * fraction)
                    .stroke(gaugeTint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(180))

                // Needle points straight up at mid-scale; (fraction - 0.5) maps the 0…1 range onto
                // -90°…+90°, so it swings to the left end at the minimum and the right at the maximum.
                GaugeNeedle()
                    .fill(DashboardTheme.primaryText)
                    .rotationEffect(.degrees((fraction - 0.5) * 180))

                Circle()
                    .fill(DashboardTheme.primaryText)
                    .frame(width: lineWidth, height: lineWidth)

                Text(ZabbixValueFormatting.format(reading.minValue, units: reading.units))
                    .font(.system(size: max(diameter * 0.07, 9), weight: .regular, design: .rounded))
                    .foregroundStyle(DashboardTheme.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .offset(x: -diameter * 0.4, y: diameter * 0.06)

                Text(ZabbixValueFormatting.format(reading.maxValue, units: reading.units))
                    .font(.system(size: max(diameter * 0.07, 9), weight: .regular, design: .rounded))
                    .foregroundStyle(DashboardTheme.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .offset(x: diameter * 0.4, y: diameter * 0.06)

                Text(centerText)
                    .font(.system(size: diameter * 0.2, weight: .bold, design: .rounded))
                    .foregroundStyle(DashboardTheme.primaryText)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .offset(y: diameter * 0.2)

                Text(reading.name)
                    .font(.system(size: max(diameter * 0.08, 10), weight: .regular, design: .rounded))
                    .foregroundStyle(DashboardTheme.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(width: diameter * 0.7)
                    .offset(y: diameter * 0.36)
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
        return DashboardTheme.accent
    }
}

/// A slim triangular gauge needle that points straight up, pivoting at the bounding box's center
/// (the gauge's arc center). `GaugeWidgetContentView` rotates it to the value's angle; the tip
/// reaches near the top of the square, so at ±90° it lines up with the arc's left/right ends.
private struct GaugeNeedle: Shape {
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let tipY = rect.minY + rect.height * 0.08
        let baseHalfWidth = max(rect.width * 0.02, 2)

        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: tipY))
        path.addLine(to: CGPoint(x: center.x - baseHalfWidth, y: center.y))
        path.addLine(to: CGPoint(x: center.x + baseHalfWidth, y: center.y))
        path.closeSubpath()
        return path
    }
}

struct HoneycombWidgetContentView: View {
    let cells: [HoneycombCell]

    private let columns = [GridItem(.adaptive(minimum: 90), spacing: 6)]

    var body: some View {
        AutoScrollingContent {
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(cells) { cell in
                    VStack(spacing: 2) {
                        Text(cell.primaryLabel)
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(DashboardTheme.primaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)

                        Text(cell.secondaryLabel)
                            .font(.system(size: 12, weight: .regular, design: .rounded))
                            .foregroundStyle(DashboardTheme.secondaryText)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, minHeight: 60)
                    .background(cell.backgroundColorHex.flatMap { Color(hex: $0) } ?? DashboardTheme.secondaryCardBackground)
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

    var body: some View {
        if rows.isEmpty {
            Text("No active triggers")
                .font(.system(size: 16, weight: .regular, design: .rounded))
                .foregroundStyle(DashboardTheme.secondaryText)
        } else {
            AutoScrollingContent {
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
                                        .fill(trigger.isProblem ? severityIndicatorColor(for: trigger.severity) : Color.green)
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
            AutoScrollingContent {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(summaries) { summary in
                        HStack(spacing: 6) {
                            Text(summary.groupName)
                                .font(.system(size: 17, weight: .medium, design: .rounded))
                                .foregroundStyle(DashboardTheme.primaryText)
                                .lineLimit(1)

                            Spacer(minLength: 6)

                            // One colored cell per severity that has problem hosts, showing the count —
                            // matching Zabbix's per-severity breakdown rather than a single total.
                            ForEach(Array(summary.countsBySeverity.enumerated()), id: \.offset) { severity, count in
                                if count > 0 {
                                    Text("\(count)")
                                        .font(.system(size: 15, weight: .bold, design: .rounded))
                                        .foregroundStyle(.white)
                                        .frame(minWidth: 26)
                                        .padding(.vertical, 3)
                                        .padding(.horizontal, 6)
                                        .background(
                                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                                .fill(severityIndicatorColor(for: severity))
                                        )
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

    var body: some View {
        AutoScrollingContent {
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

                                ForEach(Array(row.cells.enumerated()), id: \.offset) { _, cell in
                                    Text(cell)
                                        .font(.system(size: 14, weight: .regular, design: .rounded))
                                        .foregroundStyle(DashboardTheme.accent)
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

