//
//  ZabbixDashboardDetail.swift
//  ZabbixAppleTVDashboard
//
//  Created by Codex on 7/7/26.
//

import Foundation

/// Full widget layout for a single Zabbix dashboard, as returned by `dashboard.get` with `selectPages`.
nonisolated struct ZabbixDashboardDetail: Decodable, Sendable {
    /// Zabbix dashboard identifier.
    let dashboardid: String

    /// Dashboard display name.
    let name: String

    /// Default seconds each page is shown during the dashboard's own kiosk/slideshow rotation,
    /// used by a page whose own `display_period` is 0 ("inherit").
    let display_period: ZabbixNumericString?

    /// Whether Zabbix's own frontend auto-starts page rotation for this dashboard (1) or leaves
    /// it on the first page until a viewer manually starts the slideshow (0).
    let auto_start: ZabbixNumericString?

    /// Pages that make up the dashboard, each rendered and rotated through in turn.
    let pages: [ZabbixDashboardPage]
}

/// A single page (tab) within a Zabbix dashboard.
nonisolated struct ZabbixDashboardPage: Decodable, Sendable {
    /// Zabbix page identifier, stable across fetches.
    let dashboard_pageid: String?

    /// Page display name.
    let name: String?

    /// Seconds this page is shown before rotating to the next, or 0 to inherit the dashboard's
    /// own `display_period`.
    let display_period: ZabbixNumericString?

    /// Widgets placed on this page.
    let widgets: [ZabbixWidget]
}

/// A single widget's placement, type, and configuration fields.
nonisolated struct ZabbixWidget: Decodable, Sendable {
    /// Zabbix widget identifier.
    let widgetid: String

    /// Widget type, e.g. "clock", "problems", "item", "svggraph".
    let type: String

    /// Widget display name, if the user set one.
    let name: String?

    /// Grid column of the widget's top-left corner.
    let x: ZabbixNumericString

    /// Grid row of the widget's top-left corner.
    let y: ZabbixNumericString

    /// Widget width in grid columns.
    let width: ZabbixNumericString

    /// Widget height in grid rows.
    let height: ZabbixNumericString

    /// Header display mode: 0 = header shown (default), 1 = header hidden. Widgets with a hidden
    /// header (typically compact "item value" widgets with their own background color) render
    /// their own description inline rather than showing the generic card title bar.
    let view_mode: ZabbixNumericString?

    /// Widget-specific configuration fields.
    let fields: [ZabbixWidgetField]
}

/// A single configuration field on a dashboard widget.
nonisolated struct ZabbixWidgetField: Decodable, Sendable {
    /// Field name, e.g. "itemid.0".
    let name: String

    /// Field value. Zabbix always returns this as a string regardless of the field's semantic type.
    let value: String
}
