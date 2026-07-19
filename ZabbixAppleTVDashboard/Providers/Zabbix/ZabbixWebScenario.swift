//
//  ZabbixWebScenario.swift
//  ZabbixAppleTVDashboard
//
//  Created by Codex on 7/7/26.
//

import Foundation

/// A web monitoring scenario, as returned by `httptest.get`.
///
/// Ok/Failed/Unknown status is derived separately from each scenario's `web.test.fail[<name>]`
/// internal item (see `ZabbixWebFailItem` and `resolveWebMonitoring`), matching how Zabbix's own
/// Web monitoring widget classifies scenarios.
nonisolated struct ZabbixWebScenario: Decodable, Sendable {
    /// Zabbix web scenario identifier.
    let httptestid: String

    /// Scenario display name.
    let name: String

    /// Host the scenario runs against.
    let hosts: [ZabbixHostReference]
}
