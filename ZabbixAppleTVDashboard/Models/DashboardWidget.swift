//
//  DashboardWidget.swift
//  ZabbixAppleTVDashboard
//
//  Created by Codex on 7/7/26.
//

import Foundation

/// A dashboard widget resolved with the data needed to render it natively.
nonisolated struct RenderableDashboardWidget: Identifiable, Sendable {
    /// Stable widget identifier.
    let id: String

    /// Widget title shown in its card header.
    let title: String

    /// Grid position and size.
    let frame: DashboardWidgetFrame

    /// How often this widget re-fetches its data, in seconds — always a positive interval. On an
    /// unattended wall display there is deliberately no "never refresh" case: Zabbix's own "No
    /// refresh" option assumes a person can manually refresh the browser, which a kiosk with no one
    /// at the remote can't, so a widget set to it is bounded to a slow refresh rather than frozen
    /// forever. See `DashboardManager.refreshIntervalSeconds(from:)` for how each case maps.
    let refreshIntervalSeconds: Int

    /// True when Zabbix's own widget config hides the header — the generic card title bar is
    /// suppressed for these, matching real Zabbix (typically compact colored value widgets that
    /// show their own description inline instead).
    let hasHiddenHeader: Bool

    /// Native rendering for this widget.
    let kind: DashboardWidgetKind
}

/// One page of a Zabbix dashboard, resolved for display, with its own widgets and rotation
/// duration — Zabbix dashboards can have several pages that a kiosk/wall display auto-rotates
/// through (its own "Display period" per page), the same concept this mirrors.
nonisolated struct RenderableDashboardPage: Identifiable, Sendable {
    /// Stable page identifier.
    let id: String

    /// Page display name, if the user set one.
    let name: String?

    /// Widgets placed on this page.
    let widgets: [RenderableDashboardWidget]

    /// Seconds this page stays on screen before rotating to the next, mirroring Zabbix's own
    /// per-page (or dashboard-default) "Display period".
    let displaySeconds: Int
}

/// A dashboard's full page layout plus whether it should auto-rotate, matching Zabbix's own
/// "Start slideshow automatically" dashboard setting.
nonisolated struct RenderableDashboard: Sendable {
    let pages: [RenderableDashboardPage]
    let autoRotatesPages: Bool
}

/// Grid position and size for a dashboard widget, in the provider's native grid units.
nonisolated struct DashboardWidgetFrame: Sendable, Equatable {
    /// Grid column of the widget's top-left corner.
    let x: Int

    /// Grid row of the widget's top-left corner.
    let y: Int

    /// Width in grid columns.
    let width: Int

    /// Height in grid rows.
    let height: Int
}

/// Which face the "Clock" widget renders — Zabbix's own "Clock type" field ("clock_type": 0 =
/// analog, 1 = digital; absent means analog, Zabbix's own stock default, verified live against a
/// clock widget with no fields set at all that still renders as an analog face).
nonisolated enum ClockStyle: Sendable {
    case analog
    case digital
}

/// How a Clock widget should render: its face style plus which time it shows.
nonisolated struct ClockConfiguration: Sendable {
    /// Analog or digital face.
    let style: ClockStyle

    /// Timezone to display in (`tzone_timezone`), or nil for the device's local zone.
    let timeZoneIdentifier: String?

    /// For host time (`time_type = host`), seconds to add to the device's clock so it reads as the
    /// host's own time — derived from the host's `system.localtime` item (its reported time minus
    /// when that value was collected). Nil for local/server time, where the device clock is used
    /// directly (optionally shifted by `timeZoneIdentifier`).
    let hostTimeOffset: TimeInterval?

    /// The resolved `TimeZone`, or nil when the identifier is unset/invalid (fall back to local).
    var timeZone: TimeZone? {
        timeZoneIdentifier.flatMap(TimeZone.init(identifier:))
    }

    /// A calendar in the configured timezone (or the device's local zone), for the analog hands.
    var calendar: Calendar {
        var calendar = Calendar.current
        if let timeZone { calendar.timeZone = timeZone }
        return calendar
    }

    /// An hour/minute/second format in the configured timezone, for the digital face.
    var timeFormat: Date.FormatStyle {
        var format = Date.FormatStyle.dateTime.hour().minute().second()
        if let timeZone { format.timeZone = timeZone }
        return format
    }
}

/// Native renderings supported for a dashboard widget.
///
/// The graph prototype widget (tied to low-level discovery, a distinct and deeper feature),
/// favorite maps/graphs (favorites are frontend session state, not exposed by the JSON-RPC API),
/// and the URL widget (tvOS has no in-app browser) are the only Zabbix 7.0 widget types without a
/// native rendering here — see the widget build-out plan for the reasoning behind each.
nonisolated enum DashboardWidgetKind: Sendable {
    case clock(ClockConfiguration)
    case itemValue(name: String, value: String, units: String, decimalPlaces: Int, backgroundColorHex: String?, trend: ItemValueTrend?, lastUpdated: Date?, mappedText: String?)
    case problems([DashboardProblem])
    case problemsBySeverity([SeverityCount])
    case hostAvailability([HostInterfaceAvailability])
    case systemInformation(serverVersion: String, isRunning: Bool, haNodes: [SystemHANode])
    case gauge(GaugeReading)
    case honeycomb([HoneycombCell])
    case topHosts(columns: [String], rows: [TopHostsRow])
    case topTriggers([DashboardProblem])
    case triggerOverview([TriggerOverviewRow])
    case problemsByHostGroup([HostGroupProblemSummary])
    case actionLog([ActionLogEntry])
    case discoveryStatus([DiscoveryRuleStatus])
    case webMonitoring([WebScenarioSummary])
    case itemHistory([ItemHistorySeries], showTimestamp: Bool)
    case dataOverview(DataOverviewMatrix)
    case lineChart(series: [ChartSeries], window: ChartTimeWindow, stacked: Bool, showLegend: Bool, showLegendStats: Bool, yMin: Double?, yMax: Double?)
    case pieChart([ChartSlice], isDonut: Bool)
    case geomap(markers: [GeoMapMarker], defaultView: GeoMapView?)
    case networkMap(NetworkMapDiagram)
    case mapList([MapListEntry])
    case navigationTree([NavTreeNode])
    case hostList([HostListSection])
    case itemList([ItemListSection])
    case slaReport([SLAReportEntry])

    /// The widget references a specific object (item, graph, map, ...) that the authenticated
    /// account couldn't resolve — deleted, or not visible to this account's permissions. Rendered
    /// with Zabbix's own message for this state, so a limited account sees exactly what Zabbix's
    /// frontend would show it rather than a misleading "unsupported" notice. The API can't
    /// distinguish "no permission" from "doesn't exist" (both return an empty result), which is
    /// precisely why Zabbix's message names both.
    case referencedObjectUnavailable

    case unsupported(rawType: String)
}

/// Whether an item value's widget increased or decreased since its previous poll, with the
/// server-configured color for that direction — matching Zabbix's own up/down trend indicator.
nonisolated enum ItemValueTrend: Sendable {
    case up(colorHex: String)
    case down(colorHex: String)
}

/// A single active problem shown in a problems widget.
nonisolated struct DashboardProblem: Identifiable, Sendable {
    /// Stable problem identifier.
    let id: String

    /// Problem name.
    let name: String

    /// Severity, from 0 (not classified) to 5 (disaster).
    let severity: Int

    /// Host the problem was raised on, if known.
    let host: String?

    /// Date the problem started (for Top triggers, the most recent time the trigger fired).
    let since: Date

    /// Number of times the trigger fired over the widget's window — set only for the Top triggers
    /// frequency ranking, nil for the live Problems list.
    var problemCount: Int? = nil

    /// The problem's event tags to display (already limited to the widget's `show_tags` count);
    /// empty for widgets that don't show tags.
    var tags: [ProblemTag] = []
}

/// One event tag shown on a problem row.
nonisolated struct ProblemTag: Identifiable, Sendable {
    var id: String { "\(tag)=\(value)" }
    let tag: String
    let value: String

    /// "tag: value", or just the tag when it has no value (matching Zabbix's tag chips).
    var label: String { value.isEmpty ? tag : "\(tag): \(value)" }
}

/// One trigger's problem-event frequency over a window, used to rank the Top triggers widget.
nonisolated struct TriggerFrequency: Sendable, Equatable {
    /// The trigger's ID.
    let triggerID: String

    /// How many times the trigger fired in the window.
    let count: Int

    /// Display name, taken from the trigger's most recent event.
    let name: String

    /// Worst severity seen across the trigger's events in the window.
    let severity: Int

    /// Unix time of the trigger's most recent event in the window.
    let latest: Double
}

/// Number of active problems at a given severity, shown in a problems-by-severity widget.
nonisolated struct SeverityCount: Identifiable, Sendable {
    /// Severity, from 0 (not classified) to 5 (disaster).
    let severity: Int

    /// Number of active problems at this severity.
    let count: Int

    var id: Int { severity }
}

/// Availability breakdown for one monitoring interface type (or the combined "Total hosts" row),
/// shown in a host availability widget. Each count is per-host: a host contributes to "mixed"
/// when it has more than one interface of this type and they disagree on availability.
nonisolated struct HostInterfaceAvailability: Identifiable, Sendable {
    /// Human-readable interface type, e.g. "Zabbix Agent" or "SNMP", or "Total hosts".
    let interfaceTypeName: String

    /// Number of hosts with this interface type currently available.
    let available: Int

    /// Number of hosts with this interface type currently unavailable.
    let unavailable: Int

    /// Number of hosts with two or more interfaces of this type disagreeing on availability.
    let mixed: Int

    /// Number of hosts with this interface type in an unknown state.
    let unknown: Int

    var total: Int { available + unavailable + mixed + unknown }

    var id: String { interfaceTypeName }
}

/// A single item value shown as a gauge, with its scale and threshold coloring.
nonisolated struct GaugeReading: Sendable {
    /// Item display name.
    let name: String

    /// Current numeric value.
    let value: Double

    /// Gauge scale minimum.
    let minValue: Double

    /// Gauge scale maximum.
    let maxValue: Double

    /// Unit label, e.g. "%" or "°F" (the widget's `units` override when set, else the item's own
    /// units; empty when `units_show` is off).
    let units: String

    /// The widget's `decimal_places` precision for the center value (default 2).
    let decimalPlaces: Int

    /// Threshold values that color the gauge arc, in ascending order.
    let thresholds: [GaugeThreshold]

    /// A single fixed arc color ("value_arc_color"), used when the widget isn't configured with
    /// threshold color bands — Zabbix's gauge widget supports either mode.
    let fixedArcColorHex: String?

    /// The item's value-mapped label, when it has a value map, e.g. "Up" for a reading of 1. The
    /// needle still uses the numeric `value`; this is shown as the gauge's center text so it reads
    /// "Up (1.00)" rather than a bare number, matching Zabbix's own gauge.
    let mappedText: String?
}

/// A single threshold marker on a gauge.
nonisolated struct GaugeThreshold: Sendable {
    /// Value at which this threshold's color begins to apply.
    let value: Double

    /// Threshold color as a "RRGGBB" hex string.
    let colorHex: String
}

/// A single item value shown as a colored cell in a honeycomb widget.
nonisolated struct HoneycombCell: Identifiable, Sendable {
    /// Stable cell identifier.
    let id: String

    /// Expanded `primary_label` template — the larger line (default "{HOST.NAME}").
    let primaryLabel: String

    /// Expanded `secondary_label` template — the smaller line (default "{ITEM.LASTVALUE}").
    let secondaryLabel: String

    /// Threshold-driven cell color (hex, no leading '#'), or nil when the reading meets no
    /// configured threshold — the cell then uses the default card background.
    let backgroundColorHex: String?
}

/// A single host's row of column values in a top hosts widget.
nonisolated struct TopHostsRow: Identifiable, Sendable {
    /// Stable row identifier.
    let id: String

    /// Host display name.
    let hostName: String

    /// Column values, in the same order as the widget's configured columns.
    let values: [String]
}

/// A single host's active triggers, grouped for a trigger overview widget.
nonisolated struct TriggerOverviewRow: Identifiable, Sendable {
    /// Stable row identifier.
    let id: String

    /// Host display name.
    let hostName: String

    /// This host's currently active triggers.
    let triggers: [TriggerIndicator]
}

/// A single trigger indicator within a trigger overview row.
nonisolated struct TriggerIndicator: Identifiable, Sendable {
    /// Stable indicator identifier.
    let id: String

    /// Trigger description.
    let name: String

    /// Severity, from 0 (not classified) to 5 (disaster).
    let severity: Int

    /// Whether the trigger is currently in the PROBLEM state. `false` renders an OK (green) cell,
    /// which appears only when the widget's "Show" option includes non-problem triggers.
    let isProblem: Bool
}

/// Problem count and worst severity for one host group, shown in a problem hosts widget.
nonisolated struct HostGroupProblemSummary: Identifiable, Sendable {
    /// Stable summary identifier.
    let id: String

    /// Host group display name.
    let groupName: String

    /// Per-severity counts for this group (index 0…5 = Not classified…Disaster). For Problem hosts
    /// each distinct host is counted once, in the column of its worst active problem; for grouped
    /// Problems-by-severity each problem is counted at its own severity.
    let countsBySeverity: [Int]

    /// Row total — distinct problem hosts (Problem hosts) or total problems (grouped Problems-by-sv).
    var count: Int { countsBySeverity.reduce(0, +) }

    /// Highest severity with any count in this group.
    var maxSeverity: Int { countsBySeverity.lastIndex(where: { $0 > 0 }) ?? 0 }
}

/// A single sent notification or executed remote command, shown in an action log widget.
nonisolated struct ActionLogEntry: Identifiable, Sendable {
    /// Stable entry identifier.
    let id: String

    /// Recipient address, or a placeholder for remote command alerts.
    let recipient: String

    /// Notification subject or command summary.
    let subject: String

    /// Delivery status: 0 = not sent, 1 = sent/executed.
    let status: Int

    /// Date the alert was sent.
    let date: Date
}

/// A network discovery rule's status, shown in a discovery status widget.
nonisolated struct DiscoveryRuleStatus: Identifiable, Sendable {
    /// Stable rule identifier.
    let id: String

    /// Rule display name.
    let name: String

    /// Whether the rule is enabled.
    let isEnabled: Bool

    /// Number of hosts currently up under this rule.
    let upCount: Int

    /// Number of hosts currently down (lost) under this rule.
    let downCount: Int
}

/// A single web monitoring scenario, shown in a web monitoring widget.
nonisolated struct WebScenarioSummary: Identifiable, Sendable {
    /// Stable scenario identifier.
    let id: String

    /// Scenario display name.
    let name: String

    /// Host the scenario runs against, if known.
    let hostName: String?

    /// Ok / Failed / Unknown, derived from the scenario's `web.test.fail` internal check item.
    let status: WebScenarioStatus
}

/// A web scenario's current health, matching Zabbix's own Web monitoring widget states.
nonisolated enum WebScenarioStatus: Sendable, Equatable {
    /// The scenario's last run passed (`web.test.fail` == 0).
    case ok
    /// The scenario's last run failed at a step (`web.test.fail` > 0).
    case failed
    /// No status is known (no `web.test.fail` item, or it has never collected a value).
    case unknown
}

/// An item's recent historical values, shown in an item history widget.
nonisolated struct ItemHistorySeries: Identifiable, Sendable {
    /// Stable series identifier.
    let id: String

    /// Item display name.
    let itemName: String

    /// Recent values, most recent first. Each `value` is already fully formatted for display —
    /// value-mapped or unit-scaled (e.g. "4.93 GB") — so the view renders it verbatim.
    let values: [ItemHistoryPoint]
}

/// A single historical value point.
nonisolated struct ItemHistoryPoint: Identifiable, Sendable {
    /// Stable point identifier.
    let id: String

    /// Recorded value.
    let value: String

    /// Date the value was recorded.
    let date: Date
}

/// A single host/item value pair, shown in a data overview widget.
/// A hosts×items grid for the Data overview widget: one row per host (or item, when the widget's
/// orientation is transposed), one column per item (or host), each cell the item's value for that
/// host — matching Zabbix's own matrix layout rather than a flat list.
nonisolated struct DataOverviewMatrix: Sendable {
    /// Column headers (item names by default; host names when transposed).
    let columnHeaders: [String]

    /// One row per host (or item when transposed).
    let rows: [DataOverviewMatrixRow]
}

nonisolated struct DataOverviewMatrixRow: Identifiable, Sendable {
    /// Stable row identifier (the row header).
    let id: String

    /// Leading row header — the host name (or item name when transposed).
    let header: String

    /// Formatted cell values aligned with `columnHeaders`; empty for a host/item with no value.
    let cells: [String]
}

/// A single time series shown as a line on a chart widget.
nonisolated struct ChartSeries: Identifiable, Sendable {
    /// Stable series identifier.
    let id: String

    /// Series label, typically "Host: Item".
    let name: String

    /// Line color as a "RRGGBB" hex string.
    let colorHex: String

    /// The underlying item's unit string (e.g. "bps", "B", "%"), used to scale axis labels the
    /// way Zabbix's own graphs do (bps -> Kbps -> Mbps -> Gbps).
    let units: String

    /// Fill opacity (0...1) for the area drawn beneath the line, matching Zabbix's own svggraph
    /// datasets, which shade a translucent area under each line by default (its "transparency"
    /// field, 0-10, unset on most datasets but still rendered at its default rather than 0/none).
    let fillOpacity: Double

    /// Recent data points, oldest first.
    let points: [ChartPoint]
}

/// A single point on a chart series.
nonisolated struct ChartPoint: Identifiable, Sendable {
    /// Stable point identifier.
    let id: String

    /// Date the value was recorded.
    let date: Date

    /// Recorded value, or `nil` to mark a break in the line where the item reported no data for a
    /// stretch of the window — Swift Charts renders a `nil` value as a gap, so an outage shows as
    /// blank space rather than a straight line interpolated across the missing period.
    let value: Double?
}

/// The wall-clock span a chart is meant to cover, independent of where its data points actually
/// fall — used to pin the x-axis to the widget's configured window (e.g. the full "last 24 hours")
/// so periods with no data read as blank instead of the axis collapsing to just the range that
/// happens to have points.
nonisolated struct ChartTimeWindow: Sendable {
    let start: Date
    let end: Date
}

/// A single slice of a pie chart widget, showing one dataset's latest value.
nonisolated struct ChartSlice: Identifiable, Sendable {
    /// Stable slice identifier.
    let id: String

    /// Slice label, typically "Host: Item".
    let name: String

    /// Slice color as a "RRGGBB" hex string.
    let colorHex: String

    /// Latest value (drives the sector angle).
    let value: Double

    /// The value formatted for the legend with its units + precision, e.g. "1.5 Mbps"; nil hides it.
    var valueLabel: String? = nil
}

/// A host marker on a geomap widget.
nonisolated struct GeoMapMarker: Identifiable, Sendable {
    /// Stable marker identifier.
    let id: String

    /// Host display name.
    let hostName: String

    /// Latitude.
    let latitude: Double

    /// Longitude.
    let longitude: Double

    /// This host's highest active problem severity, 0 if none.
    let severity: Int
}

/// The Geomap widget's configured initial view (`default_view`): a center and a web-map zoom level,
/// used to open the map at the author's chosen location rather than auto-fitting to the markers.
nonisolated struct GeoMapView: Sendable {
    let latitude: Double
    let longitude: Double
    /// Web-map zoom level (0 = whole world, higher = closer).
    let zoom: Double
}

/// A network topology diagram for a map widget.
nonisolated struct NetworkMapDiagram: Sendable {
    /// Map canvas width in pixels, defining the coordinate space for element positions.
    let width: Int

    /// Map canvas height in pixels.
    let height: Int

    /// Decoded background image data, if the map has one configured.
    let backgroundImageData: Data?

    /// Elements placed on the map.
    let elements: [NetworkMapElement]

    /// Lines connecting pairs of elements.
    let links: [NetworkMapLink]
}

/// A single element on a network map diagram.
nonisolated struct NetworkMapElement: Identifiable, Sendable {
    /// Stable element identifier.
    let id: String

    /// Display label — the host's real name when resolvable, otherwise the map's configured label.
    let label: String

    /// X position in the map's pixel coordinate space.
    let x: Int

    /// Y position in the map's pixel coordinate space.
    let y: Int

    /// This element's highest active problem severity, 0 if none or not a host element.
    let severity: Int

    /// Decoded device-type icon image (e.g. switch, router, cloud), matching what Zabbix's own
    /// map editor shows for this element. `nil` when the element has no icon configured or its
    /// image failed to decode.
    let iconImageData: Data?
}

/// A single connecting line between two network map elements.
nonisolated struct NetworkMapLink: Identifiable, Sendable {
    /// Stable link identifier.
    let id: String

    /// First endpoint's position.
    let fromX: Int
    let fromY: Int

    /// Second endpoint's position.
    let toX: Int
    let toY: Int

    /// Line color as a "RRGGBB" hex string — the base color, or a linked trigger's color while
    /// that trigger is in the PROBLEM state.
    let colorHex: String
}

/// A single map name in a map navigation tree widget.
nonisolated struct MapListEntry: Identifiable, Sendable {
    /// Stable entry identifier.
    let id: String

    /// Map display name.
    let name: String
}

/// One node in a Map navigation tree, flattened into a depth-tagged row (depth 0 = top level).
nonisolated struct NavTreeNode: Identifiable, Sendable {
    /// Stable node identifier (the node's navtree index).
    let id: String

    /// Node label.
    let name: String

    /// Indentation depth in the tree.
    let depth: Int

    /// Whether this node links to a map (vs. being a grouping folder).
    let linksToMap: Bool

    /// The linked map's identifier, or nil for a grouping folder.
    let sysmapid: String?

    /// Worst active-problem severity for this node — its linked map's, rolled up from descendants
    /// for folders (0 = none/OK).
    let severity: Int
}

/// A single host shown in a static host navigator list.
/// A group of hosts under a `group_by` heading in the Host navigator (empty title = ungrouped).
nonisolated struct HostListSection: Identifiable, Sendable {
    let id: String
    let title: String
    let hosts: [HostListEntry]
}

/// A group of items under a `group_by` heading in the Item navigator (empty title = ungrouped).
nonisolated struct ItemListSection: Identifiable, Sendable {
    let id: String
    let title: String
    let items: [ItemListEntry]
}

nonisolated struct HostListEntry: Identifiable, Sendable {
    /// Stable entry identifier.
    let id: String

    /// Host display name.
    let name: String

    /// Number of active problems on this host.
    let problemCount: Int

    /// This host's highest active problem severity, 0 if none.
    let maxSeverity: Int
}

/// A single item shown in a static item navigator list.
nonisolated struct ItemListEntry: Identifiable, Sendable {
    /// Stable entry identifier.
    let id: String

    /// Item display name.
    let name: String

    /// Host the item belongs to.
    let hostName: String

    /// Most recent recorded value, if any.
    let lastValue: String

    /// Unit label, e.g. "%" or "°F".
    let units: String
}

/// A single SLA's configured target, shown in an SLA report widget.
/// One HA cluster node row in the System information widget's "High availability nodes" mode.
nonisolated struct SystemHANode: Identifiable, Sendable {
    /// Stable row identifier.
    let id: String

    /// Node display name ("Standalone" for the implicit unnamed node).
    let name: String

    /// Human-readable status ("Active", "Standby", "Stopped", "Unavailable").
    let statusLabel: String

    /// Whether the node is currently active — drives its status color.
    let isActive: Bool
}

nonisolated struct SLAReportEntry: Identifiable, Sendable {
    /// Stable entry identifier.
    let id: String

    /// Row label — the service name (or the SLA name when reporting a single unnamed row).
    let name: String

    /// Target SLO, e.g. "99.9%".
    let targetSLO: String

    /// Achieved SLI for the latest period, e.g. "99.95%", or nil when it couldn't be computed.
    let achievedSLI: String?

    /// Whether the achieved SLI met the target SLO, when both are known — drives pass/fail color.
    let meetsTarget: Bool?
}
