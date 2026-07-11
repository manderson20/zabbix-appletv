//
//  DashboardOpsError.swift
//  ZabbixAppleTVDashboard
//
//  Created by Codex on 7/7/26.
//

import Foundation

/// Shared error values used across app services and provider integrations.
nonisolated enum DashboardOpsError: LocalizedError, Sendable {
    case credentialEncodingFailed
    case invalidServerResponse
    case invalidServerURL
    case missingCredential
    case missingServerConfiguration
    case networkRequestFailed(Int)
    case secureStorageFailed(OSStatus)
    case settingsEncodingFailed
    case settingsDecodingFailed

    var errorDescription: String? {
        switch self {
        case .credentialEncodingFailed:
            return "The credential could not be prepared for secure storage."
        case .invalidServerResponse:
            return "The server response could not be understood."
        case .invalidServerURL:
            return "The server URL is invalid."
        case .missingCredential:
            return "No saved Zabbix credential was found."
        case .missingServerConfiguration:
            return "No Zabbix server configuration was found."
        case let .networkRequestFailed(statusCode):
            return "The server returned HTTP \(statusCode)."
        case let .secureStorageFailed(status):
            return "Secure storage failed with status \(status)."
        case .settingsEncodingFailed:
            return "Settings could not be saved."
        case .settingsDecodingFailed:
            return "Settings could not be loaded."
        }
    }
}
