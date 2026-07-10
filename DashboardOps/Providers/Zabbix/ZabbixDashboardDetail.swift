//
//  ZabbixDashboardDetail.swift
//  DashboardOps
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

    /// Pages that make up the dashboard. DashboardOps renders only the first page.
    let pages: [ZabbixDashboardPage]
}

/// A single page (tab) within a Zabbix dashboard.
nonisolated struct ZabbixDashboardPage: Decodable, Sendable {
    /// Page display name.
    let name: String?

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
