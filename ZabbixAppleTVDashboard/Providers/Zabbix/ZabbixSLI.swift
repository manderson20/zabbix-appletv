//
//  ZabbixSLI.swift
//  ZabbixAppleTVDashboard
//

import Foundation

/// The computed service-level indicator report returned by `sla.getsli` — the *actual* achieved
/// availability over one or more periods, as opposed to the SLA's configured target (`sla.get`).
///
/// `sli` is indexed `[period][service]`: the outer array is one entry per reporting period (newest
/// arrangement follows Zabbix's own ordering), the inner array aligns with `serviceids`.
nonisolated struct ZabbixSLI: Decodable, Sendable {
    /// The reporting periods covered, aligned with the outer index of `sli`.
    let periods: [Period]

    /// The service IDs reported on, aligned with the inner index of `sli`.
    let serviceids: [String]

    /// Per-period, per-service indicator cells.
    let sli: [[Cell]]

    nonisolated struct Period: Decodable, Sendable {
        let period_from: Int
        let period_to: Int
    }

    nonisolated struct Cell: Decodable, Sendable {
        /// Achieved SLI as a percentage, e.g. 99.9542.
        let sli: Double

        /// Uptime / downtime seconds in the period (returned by Zabbix; not all are displayed).
        let uptime: Int?
        let downtime: Int?
    }
}
