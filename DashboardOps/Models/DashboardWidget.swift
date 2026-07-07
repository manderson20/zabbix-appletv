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
/// Coverage starts with widget types that have simple, stable data shapes. Graph-style widgets
/// (Zabbix's "graph" and "svggraph") are intentionally left unsupported for now: their field
/// schemas are rich and have changed across Zabbix versions, and rendering them incorrectly would
/// be worse than a clear placeholder until they're verified against a live server.
nonisolated enum DashboardWidgetKind: Sendable {
    case clock
    case itemValue(name: String, value: String, units: String)
    case problems([DashboardProblem])
    case problemsBySeverity([SeverityCount])
    case hostAvailability([HostInterfaceAvailability])
    case systemOverview(hostCount: Int, itemCount: Int, problemCount: Int)
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
