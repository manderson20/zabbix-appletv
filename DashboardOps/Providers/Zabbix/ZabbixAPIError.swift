//
//  ZabbixAPIError.swift
//  DashboardOps
//
//  Created by Codex on 7/7/26.
//

import Foundation

/// Error payload returned by the Zabbix JSON-RPC API.
nonisolated struct ZabbixAPIError: Decodable, Equatable, LocalizedError, Sendable {
    /// Zabbix API error code.
    let code: Int

    /// Short error message.
    let message: String

    /// Optional detailed error data.
    let data: String?

    var errorDescription: String? {
        if let data, !data.isEmpty {
            return "\(message): \(data)"
        }

        return message
    }
}
