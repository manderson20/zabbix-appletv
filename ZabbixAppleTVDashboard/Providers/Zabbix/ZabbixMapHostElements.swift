//
//  ZabbixMapHostElements.swift
//  ZabbixAppleTVDashboard
//

import Foundation

/// A minimal `map.get` result — just a map's identifier and its elements — used to compute each Map
/// navigation-tree node's severity from the hosts on its linked map, without fetching the full map
/// (background, links, icons) the network-map widget needs.
nonisolated struct ZabbixMapHostElements: Decodable, Sendable {
    /// Zabbix map identifier.
    let sysmapid: String

    /// The map's elements; only host elements (`elementtype` 0) contribute a severity.
    let selements: [ZabbixMapElement]
}
