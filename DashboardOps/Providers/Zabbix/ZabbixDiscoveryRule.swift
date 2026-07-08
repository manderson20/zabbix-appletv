//
//  ZabbixDiscoveryRule.swift
//  DashboardOps
//
//  Created by Codex on 7/7/26.
//

import Foundation

/// A network discovery rule, as returned by `drule.get`.
nonisolated struct ZabbixDiscoveryRule: Decodable, Sendable {
    /// Zabbix discovery rule identifier.
    let druleid: String

    /// Rule display name.
    let name: String

    /// 0 = enabled, 1 = disabled.
    let status: ZabbixNumericString
}

/// A single host discovered by a rule, as returned by `dhost.get`.
nonisolated struct ZabbixDiscoveredHost: Decodable, Sendable {
    /// Discovery rule this host was found by.
    let druleid: String

    /// 0 = up (discovered/alive), 1 = down (lost).
    let status: ZabbixNumericString
}
