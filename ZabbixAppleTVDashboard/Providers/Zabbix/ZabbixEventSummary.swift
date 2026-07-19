//
//  ZabbixEventSummary.swift
//  ZabbixAppleTVDashboard
//

import Foundation

/// A trigger problem event, as returned by `event.get`. Used to rank triggers by how often they
/// went into problem state over a time window (the "Top triggers" widget), rather than by their
/// current severity.
nonisolated struct ZabbixEventSummary: Decodable, Sendable {
    /// Zabbix event identifier.
    let eventid: String

    /// The trigger that raised the event (its trigger ID).
    let objectid: String

    /// Event severity, from 0 (not classified) to 5 (disaster).
    let severity: ZabbixNumericString

    /// Event (trigger) display name.
    let name: String

    /// Event time as a Unix-timestamp string.
    let clock: String
}
