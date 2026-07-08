//
//  ZabbixSLA.swift
//  DashboardOps
//
//  Created by Codex on 7/7/26.
//

import Foundation

/// An SLA definition, as returned by `sla.get`.
///
/// This app shows only the SLA's configured target, not a computed period report (which requires
/// the separate `sla.getsla` method with a service and time period) — not yet verified against a
/// live example, as no SLA was configured on the server this was checked against.
nonisolated struct ZabbixSLA: Decodable, Sendable {
    /// Zabbix SLA identifier.
    let slaid: String

    /// SLA display name.
    let name: String

    /// Target SLO percentage, e.g. "99.9000".
    let slo: String
}
