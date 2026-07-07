//
//  ZabbixNumericString.swift
//  DashboardOps
//
//  Created by Codex on 7/7/26.
//

import Foundation

/// Decodes a Zabbix API integer that the API may return as either a JSON number or a numeric string.
///
/// Zabbix's JSON-RPC API is inconsistent about this across object types and versions, so widget
/// geometry and similar numeric fields are decoded through this wrapper rather than `Int` directly.
nonisolated struct ZabbixNumericString: Decodable, Equatable, Sendable {
    /// The decoded integer value.
    let intValue: Int

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let value = try? container.decode(Int.self) {
            intValue = value
            return
        }

        let stringValue = try container.decode(String.self)
        guard let value = Int(stringValue) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected an integer or integer string, found \"\(stringValue)\"."
            )
        }

        intValue = value
    }
}
