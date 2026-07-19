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

/// Native renderings supported for a dashboard widget.
///
/// The graph prototype widget (tied to low-level discovery, a distinct and deeper feature),
/// favorite maps/graphs (favorites are frontend session state, not exposed by the JSON-RPC API),
/// and the URL widget (tvOS has no in-app browser) are the only Zabbix 7.0 widget types without a
/// native rendering here — see the widget build-out plan for the reasoning behind each.
nonisolated enum DashboardWidgetKind: Sendable {
    case clock(ClockStyle)
    case itemValue(name: String, value: String, units: String, backgroundColorHex: String?, trend: ItemValueTrend?, lastUpdated: Date?, mappedText: String?)
    case problems([DashboardProblem])
    case problemsBySeverity([SeverityCount])
    case hostAvailability([HostInterfaceAvailability])
    case systemInformation(serverVersion: String, isRunning: Bool)
    case gauge(GaugeReading)
    case honeycomb([HoneycombCell])
    case topHosts(columns: [String], rows: [TopHostsRow])
    case topTriggers([DashboardProblem])
    case triggerOverview([TriggerOverviewRow])
    case problemsByHostGroup([HostGroupProblemSummary])
    case actionLog([ActionLogEntry])
    case discoveryStatus([DiscoveryRuleStatus])
    case webMonitoring([WebScenarioSummary])
    case itemHistory([ItemHistorySeries])
    case dataOverview([DataOverviewEntry])
    case lineChart(series: [ChartSeries], window: ChartTimeWindow)
    case pieChart([ChartSlice])
    case geomap([GeoMapMarker])
    case networkMap(NetworkMapDiagram)
    case mapList([MapListEntry])
    case hostList([HostListEntry])
    case itemList([ItemListEntry])
    case slaReport([SLAReportEntry])
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

    /// Date the problem started.
    let since: Date
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

    /// Unit label, e.g. "%" or "°F".
    let units: String

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

    /// Primary label, typically the host name.
    let primaryLabel: String

    /// Secondary label, typically the item name or value.
    let secondaryLabel: String

    /// Current value.
    let value: String

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

    /// Number of distinct hosts in this group with at least one active problem (not the total
    /// number of problems — a host with several open problems still counts once).
    let count: Int

    /// Highest severity among this group's active problems.
    let maxSeverity: Int
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

    /// Unit label, e.g. "%" or "°F".
    let units: String

    /// Recent values, most recent first.
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
nonisolated struct DataOverviewEntry: Identifiable, Sendable {
    /// Stable entry identifier.
    let id: String

    /// Host display name.
    let hostName: String

    /// Item display name.
    let itemName: String

    /// Current value.
    let value: String

    /// Unit label, e.g. "%" or "°F".
    let units: String
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

    /// Latest value.
    let value: Double
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

/// A single host shown in a static host navigator list.
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
nonisolated struct SLAReportEntry: Identifiable, Sendable {
    /// Stable entry identifier.
    let id: String

    /// SLA display name.
    let name: String

    /// Target SLO, e.g. "99.9%".
    let targetSLO: String
}
