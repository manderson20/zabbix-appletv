//
//  ZabbixProvider.swift
//  DashboardOps
//
//  Created by Codex on 7/7/26.
//

import Foundation

/// Provider metadata for the Zabbix Phase 1 integration target.
nonisolated struct ZabbixProvider: DashboardProvider {
    /// Stable provider identifier.
    let id = DashboardProviderKind.zabbix.rawValue

    /// Human-readable provider name.
    let displayName = "Zabbix"

    /// Provider family.
    let kind = DashboardProviderKind.zabbix

    /// Zabbix is the only supported Version 1 provider.
    let supportStatus = ProviderSupportStatus.supported
}
