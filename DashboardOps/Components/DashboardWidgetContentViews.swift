//
//  DashboardWidgetContentViews.swift
//  DashboardOps
//
//  Created by Codex on 7/7/26.
//

import Charts
import MapKit
import SwiftUI
import UIKit

struct GeomapWidgetContentView: View {
    let markers: [GeoMapMarker]

    private var cameraPosition: MapCameraPosition {
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

struct HostListWidgetContentView: View {
    let hosts: [HostListEntry]

    var body: some View {
        if hosts.isEmpty {
            Text("No hosts match this widget's filters")
                .font(.system(size: 16, weight: .regular, design: .rounded))
                .foregroundStyle(DashboardTheme.secondaryText)
        } else {
            AutoScrollingContent {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(hosts) { host in
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
                    }
                }
            }
        }
    }
}

struct ItemListWidgetContentView: View {
    let items: [ItemListEntry]

    var body: some View {
        if items.isEmpty {
            Text("No items match this widget's filters")
                .font(.system(size: 16, weight: .regular, design: .rounded))
                .foregroundStyle(DashboardTheme.secondaryText)
        } else {
            AutoScrollingContent {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(items) { item in
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.name)
                                    .font(.system(size: 15, weight: .medium, design: .rounded))
                                    .foregroundStyle(DashboardTheme.primaryText)
                                    .lineLimit(1)
                                Text(item.hostName)
                                    .font(.system(size: 12, weight: .regular, design: .rounded))
                                    .foregroundStyle(DashboardTheme.secondaryText)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Text(item.units.isEmpty ? item.lastValue : "\(item.lastValue) \(item.units)")
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .foregroundStyle(DashboardTheme.accent)
                        }
                    }
                }
            }
        }
    }
}

struct SLAReportWidgetContentView: View {
    let entries: [SLAReportEntry]

    var body: some View {
        if entries.isEmpty {
            Text("No SLA selected, or no SLAs configured")
                .font(.system(size: 16, weight: .regular, design: .rounded))
                .foregroundStyle(DashboardTheme.secondaryText)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(entries) { entry in
                    HStack {
                        Text(entry.name)
                            .font(.system(size: 17, weight: .medium, design: .rounded))
                            .foregroundStyle(DashboardTheme.primaryText)
                            .lineLimit(1)
                        Spacer()
                        Text("Target \(entry.targetSLO)")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(DashboardTheme.accent)
                    }
                }
            }
        }
    }
}

struct LineChartWidgetContentView: View {
    let series: [ChartSeries]

    private var units: String { series.first?.units ?? "" }

    private var yAxisScale: ZabbixValueFormatting.Scale {
        let maxValue = series.flatMap(\.points).map(\.value).max() ?? 0
        return ZabbixValueFormatting.scale(forMaxMagnitude: maxValue, units: units)
    }

    /// Builds one point's marks in their own function (rather than inline in the `Chart` closure)
    /// so the type checker has a small, isolated expression to solve instead of the whole nested
    /// `Chart { ForEach { ForEach { ... } } }` tree at once — the inline form timed out entirely.
    ///
    /// `foregroundStyle(by:)` (a plottable grouping value, not a bare `Color`) is what tells Swift
    /// Charts these points belong to distinct series — without it, points from different series
    /// interleave into one zigzagging path sorted by x-position instead of staying separate.
    /// Swift Charts also stacks `AreaMark`s by default whenever they're grouped this way (as if
    /// plotting composition, like a stacked area chart); `.position(.overlay)` is what makes each
    /// series' fill independently start from 0 instead of piling on top of the others, which was
    /// inflating the visible peak to the sum of every series rather than each one's own value.
    @ChartContentBuilder
    private func marks(for point: ChartPoint, in line: ChartSeries) -> some ChartContent {
        // Explicit yStart/yEnd (rather than the single-`y` initializer) bypasses Swift Charts'
        // automatic stacking baseline — with a plain `y:` value, grouping by `foregroundStyle(by:)`
        // makes each series' baseline the sum of the ones before it (as if plotting composition),
        // which was inflating the visible peak to the sum of every series rather than each one's
        // own value. Pinning yStart to 0 draws each series' fill independently from the bottom.
        AreaMark(x: .value("Time", point.date), yStart: .value("Baseline", 0), yEnd: .value(line.name, point.value))
            .foregroundStyle(by: .value("Series", line.name))
            .opacity(line.fillOpacity)

        LineMark(x: .value("Time", point.date), y: .value(line.name, point.value))
            .foregroundStyle(by: .value("Series", line.name))
    }

    var body: some View {
        if series.allSatisfy({ $0.points.isEmpty }) {
            Text("No data in the last 24 hours")
                .font(.system(size: 16, weight: .regular, design: .rounded))
                .foregroundStyle(DashboardTheme.secondaryText)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Chart {
                    ForEach(series) { line in
                        ForEach(line.points) { point in
                            marks(for: point, in: line)
                        }
                    }
                }
                .chartForegroundStyleScale(
                    domain: series.map(\.name),
                    range: series.map { Color(hex: $0.colorHex) ?? DashboardTheme.accent }
                )
                // Swift Charts' built-in legend doesn't wrap long labels within the card's actual
                // width — it can run entries off the edge instead — so it's hidden in favor of
                // the wrapping `ChartLegendView` below, which we fully control.
                .chartLegend(.hidden)
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

                if series.count > 1 {
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

    private let columns = [GridItem(.adaptive(minimum: 220, maximum: 320), spacing: 12, alignment: .leading)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 4) {
            ForEach(series) { line in
                HStack(spacing: 5) {
                    Circle()
                        .fill(Color(hex: line.colorHex) ?? DashboardTheme.accent)
                        .frame(width: 8, height: 8)

                    // Zabbix interface item names put the part that actually distinguishes two
                    // series of the same graph — "Bits sent" vs "Bits received" — at the very end
                    // (e.g. "BSD-WAN-CV: Interface Port 1: Bits received"). Tail truncation cut
                    // exactly that off, leaving two legend entries that read identically and no
                    // way to tell which color was which. Eliding the middle instead keeps both the
                    // host/interface prefix and the sent/received suffix visible.
                    Text(line.name)
                        .font(.system(size: 11, weight: .regular, design: .rounded))
                        .foregroundStyle(DashboardTheme.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
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

    var body: some View {
        GeometryReader { geometry in
            // The arc only sweeps 270° (a `trim` to 0.75), leaving a 90° gap at the bottom of the
            // circle's own bounding square that's otherwise just blank — the item name fits there
            // instead of needing a separate row underneath, so the ring itself can claim nearly
            // the widget's full available height rather than sharing it with a second line.
            let diameter = max(min(geometry.size.width, geometry.size.height), 40)

            ZStack {
                Circle()
                    .trim(from: 0, to: 0.75)
                    .stroke(DashboardTheme.secondaryCardBackground, style: StrokeStyle(lineWidth: max(diameter * 0.09, 6), lineCap: .round))
                    .rotationEffect(.degrees(135))

                Circle()
                    .trim(from: 0, to: 0.75 * fraction)
                    .stroke(gaugeTint, style: StrokeStyle(lineWidth: max(diameter * 0.09, 6), lineCap: .round))
                    .rotationEffect(.degrees(135))

                Text(ZabbixValueFormatting.format(reading.value, units: reading.units))
                    .font(.system(size: diameter * 0.22, weight: .bold, design: .rounded))
                    .foregroundStyle(DashboardTheme.primaryText)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .offset(y: -diameter * 0.08)

                Text(reading.name)
                    .font(.system(size: max(diameter * 0.08, 10), weight: .regular, design: .rounded))
                    .foregroundStyle(DashboardTheme.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(width: diameter * 0.56)
                    .offset(y: diameter * 0.42)
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

struct HoneycombWidgetContentView: View {
    let cells: [HoneycombCell]

    private let columns = [GridItem(.adaptive(minimum: 90), spacing: 6)]

    var body: some View {
        AutoScrollingContent {
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
            AutoScrollingContent {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(summaries) { summary in
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
    let entries: [DataOverviewEntry]

    var body: some View {
        if entries.isEmpty {
            Text("No items match this widget's filters")
                .font(.system(size: 16, weight: .regular, design: .rounded))
                .foregroundStyle(DashboardTheme.secondaryText)
        } else {
            AutoScrollingContent {
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

