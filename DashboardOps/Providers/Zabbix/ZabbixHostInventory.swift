//
//  ZabbixHostInventory.swift
//  DashboardOps
//
//  Created by Codex on 7/7/26.
//

import Foundation

/// A host with its inventory location fields, as returned by `host.get` with `selectInventory`.
nonisolated struct ZabbixHostWithInventory: Decodable, Sendable {
    /// Zabbix host identifier.
    let hostid: String

    /// Host display name.
    let name: String

    /// The host's inventory data.
    let inventory: ZabbixHostInventory
}

/// A host's inventory location fields.
///
/// Zabbix returns `inventory` as an empty array `[]` when inventory isn't populated for a host,
/// but as a keyed object when it is — verified against a live Zabbix 7.0 server. This type decodes
/// either shape, leaving the coordinates `nil` in the array case.
nonisolated struct ZabbixHostInventory: Decodable, Sendable {
    /// Latitude, as a string per Zabbix API convention. `nil` when inventory isn't populated.
    let locationLatitude: String?

    /// Longitude, as a string per Zabbix API convention. `nil` when inventory isn't populated.
    let locationLongitude: String?

    private enum CodingKeys: String, CodingKey {
        case locationLatitude = "location_lat"
        case locationLongitude = "location_lon"
    }

    init(from decoder: Decoder) throws {
        guard let keyed = try? decoder.container(keyedBy: CodingKeys.self) else {
            locationLatitude = nil
            locationLongitude = nil
            return
        }

        locationLatitude = try keyed.decodeIfPresent(String.self, forKey: .locationLatitude)
        locationLongitude = try keyed.decodeIfPresent(String.self, forKey: .locationLongitude)
    }
}
