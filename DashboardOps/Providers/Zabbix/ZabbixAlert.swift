//
//  ZabbixAlert.swift
//  DashboardOps
//
//  Created by Codex on 7/7/26.
//

import Foundation

/// A sent notification or executed remote command, as returned by `alert.get`.
nonisolated struct ZabbixAlert: Decodable, Sendable {
    /// Zabbix alert identifier.
    let alertid: String

    /// Unix timestamp the alert was sent, as a string per Zabbix API convention.
    let clock: String

    /// Notification subject line. Empty for remote command alerts.
    let subject: String?

    /// Notification body or remote command output.
    let message: String?

    /// Delivery status: 0 = not sent, 1 = sent/executed.
    let status: ZabbixNumericString

    /// Recipient address (email, phone number, etc.). Empty for remote command alerts.
    let sendto: String?

    /// Alert type: 0 = notification message, 1 = remote command.
    let alerttype: ZabbixNumericString
}
