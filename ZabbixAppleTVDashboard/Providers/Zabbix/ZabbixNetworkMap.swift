//
//  ZabbixNetworkMap.swift
//  ZabbixAppleTVDashboard
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

    /// Background image identifier. "0" means no background image is configured.
    let backgroundid: String

    /// Elements (hosts, images, host groups, or sub-maps) placed on the map.
    let selements: [ZabbixMapElement]

    /// Lines connecting pairs of elements.
    let links: [ZabbixMapLink]

    /// Drawn shapes (rectangles/ellipses with optional text) — how floor-plan style maps annotate
    /// their background (requested via `selectShapes`; absent on older fetch paths).
    let shapes: [ZabbixMapShape]?

    /// Free-standing drawn lines (requested via `selectLines`).
    let lines: [ZabbixMapFreeLine]?
}

/// A drawn shape on a map: `type` 0 = rectangle, 1 = ellipse.
nonisolated struct ZabbixMapShape: Decodable, Sendable {
    let sysmap_shapeid: String
    let type: ZabbixNumericString
    let x: ZabbixNumericString
    let y: ZabbixNumericString
    let width: ZabbixNumericString
    let height: ZabbixNumericString
    /// Shape label text (may be empty).
    let text: String
    /// Text color as "RRGGBB".
    let font_color: String?
    let font_size: ZabbixNumericString?
    /// Border: 0 = none, otherwise drawn at `border_width` in `border_color`.
    let border_type: ZabbixNumericString?
    let border_width: ZabbixNumericString?
    let border_color: String?
    /// Fill color as "RRGGBB"; empty means transparent.
    let background_color: String?
}

/// A free-standing drawn line on a map.
nonisolated struct ZabbixMapFreeLine: Decodable, Sendable {
    let sysmap_shapeid: String
    let x1: ZabbixNumericString
    let y1: ZabbixNumericString
    let x2: ZabbixNumericString
    let y2: ZabbixNumericString
    let line_type: ZabbixNumericString?
    let line_width: ZabbixNumericString?
    let line_color: String?
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

    /// The default-state icon shown for this element (e.g. "Switch_(64)", "Cloud_(128)") —
    /// verified live to reference a real device-type icon image, not just a status indicator.
    /// "0" means no icon is configured.
    let iconid_off: String

    /// The underlying object(s) this element represents, e.g. `[{"hostid": "10084"}]` for a host
    /// element. Empty for image elements.
    let elements: [ZabbixMapElementReference]
}

/// A map element's underlying object reference. Which identifier is present depends on the owning
/// element's `elementtype`.
nonisolated struct ZabbixMapElementReference: Decodable, Sendable {
    /// Host identifier, present for host-type (`elementtype` 0) elements.
    let hostid: String?

    /// Trigger identifier, present for trigger-type (`elementtype` 2) elements.
    let triggerid: String?

    /// Host group identifier, present for host-group-type (`elementtype` 3) elements.
    let groupid: String?

    /// Submap identifier, present for map-type (`elementtype` 1) elements.
    let sysmapid: String?
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

/// An uploaded image's base64-encoded content, as returned by `image.get` with `select_image`.
nonisolated struct ZabbixImage: Decodable, Sendable {
    /// Zabbix image identifier.
    let imageid: String

    /// Base64-encoded image data.
    let image: String
}
