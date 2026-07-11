//
//  ZabbixHostListEntry.swift
//  ZabbixAppleTVDashboard
//
//  Created by Codex on 7/7/26.
//

import Foundation

/// A minimal host listing, as returned by `host.get`.
nonisolated struct ZabbixHostListEntry: Decodable, Sendable {
    /// Zabbix host identifier.
    let hostid: String

    /// Host display name.
    let name: String
}
