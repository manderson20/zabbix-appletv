//
//  ZabbixAPIResponse.swift
//  DashboardOps
//
//  Created by Codex on 7/7/26.
//

import Foundation

/// JSON-RPC response returned by the Zabbix API.
nonisolated struct ZabbixAPIResponse<Result>: Decodable, Sendable where Result: Decodable & Sendable {
    /// JSON-RPC version returned by the API.
    let jsonrpc: String

    /// Successful method result.
    let result: Result?

    /// Error returned by the API.
    let error: ZabbixAPIError?

    /// Matching client request identifier.
    let id: Int?

    /// Returns a successful result or throws the API error.
    func resolvedResult() throws -> Result {
        if let result {
            return result
        }

        if let error {
            throw error
        }

        throw DashboardOpsError.invalidServerResponse
    }
}
