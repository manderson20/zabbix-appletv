//
//  DashboardProviderKind.swift
//  ZabbixAppleTVDashboard
//
//  Created by Codex on 7/7/26.
//

import Foundation

/// Identifies the infrastructure product or web source that owns a dashboard.
nonisolated enum DashboardProviderKind: String, CaseIterable, Codable, Sendable {
    case zabbix
    case busline
}
