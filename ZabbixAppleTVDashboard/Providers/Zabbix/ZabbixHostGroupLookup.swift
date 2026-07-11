//
//  ZabbixHostGroupLookup.swift
//  ZabbixAppleTVDashboard
//
//  Created by Codex on 7/7/26.
//

import Foundation

/// A host's group memberships, as returned by `host.get` with `selectHostGroups`.
///
/// Note the response key is `hostgroups` (verified against a live Zabbix 7.0 server), not
/// `hostGroups` or `groups`.
nonisolated struct ZabbixHostGroupLookup: Decodable, Sendable {
    /// Zabbix host identifier.
    let hostid: String

    /// Host display name.
    let name: String

    /// Host groups this host belongs to.
    let hostgroups: [ZabbixHostGroupReference]
}

/// A minimal host group reference.
nonisolated struct ZabbixHostGroupReference: Decodable, Sendable {
    /// Zabbix host group identifier.
    let groupid: String

    /// Host group display name.
    let name: String
}
