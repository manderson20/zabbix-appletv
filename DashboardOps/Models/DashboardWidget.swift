//
//  DashboardWidget.swift
//  DashboardOps
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

    /// Native rendering for this widget.
    let kind: DashboardWidgetKind
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

/// Native renderings supported for a dashboard widget.
///
/// Chart widgets ("graph", "svggraph", "graphprototype", "piechart"), map widgets ("map",
/// "geomap", "mapnavtree", "favmaps"), and the URL widget are handled separately from this initial
/// tier — see the widget build-out plan for status.
nonisolated enum DashboardWidgetKind: Sendable {
    case clock
    case itemValue(name: String, value: String, units: String)
    case problems([DashboardProblem])
    case problemsBySeverity([SeverityCount])
    case hostAvailability([HostInterfaceAvailability])
    case systemOverview(hostCount: Int, itemCount: Int, problemCount: Int)
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
    case unsupported(rawType: String)
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

/// Availability breakdown for one monitoring interface type, shown in a host availability widget.
nonisolated struct HostInterfaceAvailability: Identifiable, Sendable {
    /// Human-readable interface type, e.g. "Zabbix Agent" or "SNMP".
    let interfaceTypeName: String

    /// Number of hosts with this interface type currently available.
    let available: Int

    /// Number of hosts with this interface type currently unavailable.
    let unavailable: Int

    /// Number of hosts with this interface type in an unknown state.
    let unknown: Int

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
}

/// Problem count and worst severity for one host group, shown in a problem hosts widget.
nonisolated struct HostGroupProblemSummary: Identifiable, Sendable {
    /// Stable summary identifier.
    let id: String

    /// Host group display name.
    let groupName: String

    /// Number of active problems across hosts in this group.
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
