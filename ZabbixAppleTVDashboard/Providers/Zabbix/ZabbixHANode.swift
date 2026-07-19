//
//  ZabbixHANode.swift
//  ZabbixAppleTVDashboard
//

import Foundation

/// A Zabbix HA cluster node, as returned by `hanode.get` (Zabbix 6.0+). Drives the System
/// information widget's "High availability nodes" mode and a real server-running signal (the server
/// is up when some node is active). A standalone server with no HA configured returns no nodes.
nonisolated struct ZabbixHANode: Decodable, Sendable {
    /// Node name; empty for the implicit standalone node.
    let name: String

    /// Node status: 0 = standby, 1 = stopped, 2 = unavailable, 3 = active.
    let status: ZabbixNumericString
}
