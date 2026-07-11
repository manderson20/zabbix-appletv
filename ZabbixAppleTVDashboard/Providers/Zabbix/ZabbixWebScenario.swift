//
//  ZabbixWebScenario.swift
//  ZabbixAppleTVDashboard
//
//  Created by Codex on 7/7/26.
//

import Foundation

/// A web monitoring scenario, as returned by `httptest.get`.
///
/// Zabbix's own Web Monitoring widget classifies each scenario as Ok/Failed/Unknown by inspecting
/// the scenario's associated internal check items and last-failed-step trigger, a derivation this
/// app does not yet replicate. Scenarios are shown by name and host only, without a fabricated
/// status, until that's verified against a server that actually has web scenarios configured.
nonisolated struct ZabbixWebScenario: Decodable, Sendable {
    /// Zabbix web scenario identifier.
    let httptestid: String

    /// Scenario display name.
    let name: String

    /// Host the scenario runs against.
    let hosts: [ZabbixHostReference]
}
