//
//  ZabbixDashboardSummary.swift
//  ZabbixAppleTVDashboard
//
//  Created by Codex on 7/7/26.
//

import Foundation

/// Dashboard metadata returned by the Zabbix `dashboard.get` API method.
nonisolated struct ZabbixDashboardSummary: Decodable, Equatable, Sendable {
    /// Zabbix dashboard identifier.
    let dashboardid: String

    /// Dashboard display name.
    let name: String
}
