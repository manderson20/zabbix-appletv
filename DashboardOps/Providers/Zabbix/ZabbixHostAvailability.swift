//
//  ZabbixHostAvailability.swift
//  DashboardOps
//
//  Created by Codex on 7/7/26.
//

import Foundation

/// A host's interfaces, as returned by `host.get` with `selectInterfaces`.
nonisolated struct ZabbixHostAvailability: Decodable, Sendable {
    /// Zabbix host identifier.
    let hostid: String

    /// The host's monitoring interfaces.
    let interfaces: [ZabbixHostInterface]
}

/// A single monitoring interface on a host.
nonisolated struct ZabbixHostInterface: Decodable, Sendable {
    /// Interface type: 1 = Zabbix agent, 2 = SNMP, 3 = IPMI, 4 = JMX.
    let type: ZabbixNumericString

    /// Availability: 0 = unknown, 1 = available, 2 = unavailable.
    let available: ZabbixNumericString
}
