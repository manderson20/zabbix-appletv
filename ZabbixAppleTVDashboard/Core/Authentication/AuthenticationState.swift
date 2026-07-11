//
//  AuthenticationState.swift
//  ZabbixAppleTVDashboard
//
//  Created by Codex on 7/7/26.
//

import Foundation

/// High-level authentication state for future provider sessions.
nonisolated enum AuthenticationState: String, Codable, Sendable {
    case notConfigured
    case signedOut
    case signedIn
    case expired
}
