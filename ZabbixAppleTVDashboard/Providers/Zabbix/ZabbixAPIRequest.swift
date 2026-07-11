//
//  ZabbixAPIRequest.swift
//  ZabbixAppleTVDashboard
//
//  Created by Codex on 7/7/26.
//

import Foundation

/// JSON-RPC request sent to the Zabbix API.
nonisolated struct ZabbixAPIRequest<Parameters>: Encodable, Sendable where Parameters: Encodable & Sendable {
    /// JSON-RPC version implemented by Zabbix.
    let jsonrpc = "2.0"

    /// API method name.
    let method: String

    /// Method parameters.
    let params: Parameters

    /// Client request identifier.
    let id: Int
}
