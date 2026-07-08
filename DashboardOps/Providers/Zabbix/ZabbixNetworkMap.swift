//
//  ZabbixNetworkMap.swift
//  DashboardOps
//
//  Created by Codex on 7/7/26.
//

import Foundation

/// A network map's name only, as returned by a lightweight `map.get` listing call.
nonisolated struct ZabbixMapSummary: Decodable, Sendable {
    /// Zabbix map identifier.
    let sysmapid: String

    /// Map display name.
    let name: String
}

/// A network topology map, as returned by `map.get` with `selectSelements`/`selectLinks`.
nonisolated struct ZabbixNetworkMap: Decodable, Sendable {
    /// Zabbix map identifier.
    let sysmapid: String

    /// Map display name.
    let name: String

    /// Map canvas width in pixels, defining the coordinate space for element positions.
    let width: ZabbixNumericString

    /// Map canvas height in pixels.
    let height: ZabbixNumericString

    /// Elements (hosts, images, host groups, or sub-maps) placed on the map.
    let selements: [ZabbixMapElement]

    /// Lines connecting pairs of elements.
    let links: [ZabbixMapLink]
}

/// A single element on a network map.
nonisolated struct ZabbixMapElement: Decodable, Sendable {
    /// Zabbix map element identifier, referenced by `links[].selementid1`/`selementid2`.
    let selementid: String

    /// Element type: 0 = host, 1 = map, 2 = trigger, 3 = host group, 4 = image.
    let elementtype: ZabbixNumericString

    /// Configured label. May contain unresolved macros like "{HOST.NAME}" for host elements —
    /// prefer resolving the host's real name via `elements[].hostid` instead of parsing this.
    let label: String

    /// X position in the map's pixel coordinate space.
    let x: ZabbixNumericString

    /// Y position in the map's pixel coordinate space.
    let y: ZabbixNumericString

    /// The underlying object(s) this element represents, e.g. `[{"hostid": "10084"}]` for a host
    /// element. Empty for image elements.
    let elements: [ZabbixMapElementReference]
}

/// A map element's underlying object reference.
nonisolated struct ZabbixMapElementReference: Decodable, Sendable {
    /// Host identifier, present for host-type (`elementtype` 0) elements.
    let hostid: String?
}

/// A single connecting line between two map elements.
nonisolated struct ZabbixMapLink: Decodable, Sendable {
    /// Zabbix link identifier.
    let linkid: String

    /// First endpoint's `selementid`.
    let selementid1: String

    /// Second endpoint's `selementid`.
    let selementid2: String

    /// Base line color as a "RRGGBB" hex string, shown when no associated trigger is a problem.
    let color: String

    /// Triggers that, when in the PROBLEM state, override the line's color.
    let linktriggers: [ZabbixMapLinkTrigger]
}

/// A trigger-based color override on a map link.
nonisolated struct ZabbixMapLinkTrigger: Decodable, Sendable {
    /// Zabbix trigger identifier.
    let triggerid: String

    /// Override color as a "RRGGBB" hex string, applied while this trigger is in the PROBLEM state.
    let color: String
}
