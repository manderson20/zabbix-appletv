//
//  ZabbixWebFailItem.swift
//  ZabbixAppleTVDashboard
//

import Foundation

/// A web scenario's `web.test.fail[<scenario name>]` internal check item, as returned by `item.get`
/// with `webitems: true`. Its `lastvalue` is the number of the step that last failed — 0 means the
/// scenario passed — which is how Zabbix's Web monitoring widget derives Ok/Failed status.
nonisolated struct ZabbixWebFailItem: Decodable, Sendable {
    /// Item key, e.g. `web.test.fail[Homepage]`.
    let key_: String

    /// Failed-step number as a string: "0" when the scenario passed, absent when never collected.
    let lastvalue: String?

    /// The host the item (and its scenario) belongs to.
    let hostid: String
}
