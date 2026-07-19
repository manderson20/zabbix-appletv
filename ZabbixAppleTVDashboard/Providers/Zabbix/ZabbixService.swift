//
//  ZabbixService.swift
//  ZabbixAppleTVDashboard
//

import Foundation

/// An IT service, as returned by `service.get`. Used to label SLA report rows with their service
/// name rather than a bare service ID.
nonisolated struct ZabbixService: Decodable, Sendable {
    /// Zabbix service identifier.
    let serviceid: String

    /// Service display name.
    let name: String
}
