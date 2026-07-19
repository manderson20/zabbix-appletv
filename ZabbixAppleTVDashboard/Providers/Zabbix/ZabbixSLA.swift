//
//  ZabbixSLA.swift
//  ZabbixAppleTVDashboard
//
//  Created by Codex on 7/7/26.
//

import Foundation

/// An SLA definition, as returned by `sla.get` — its name and configured target SLO. The achieved
/// SLI for the latest period is computed separately via `sla.getsli` (see `ZabbixSLI`).
nonisolated struct ZabbixSLA: Decodable, Sendable {
    /// Zabbix SLA identifier.
    let slaid: String

    /// SLA display name.
    let name: String

    /// Target SLO percentage, e.g. "99.9000".
    let slo: String
}
