//
//  UserSession.swift
//  DashboardOps
//
//  Created by Codex on 7/7/26.
//

import Foundation

/// Represents an authenticated provider session.
nonisolated struct UserSession: Identifiable, Codable, Equatable, Sendable {
    /// Stable local session identifier.
    let id: UUID

    /// Provider family associated with the session.
    var providerKind: DashboardProviderKind

    /// Server configuration used to create the session.
    var serverConfigurationID: ServerConfiguration.ID?

    /// Current authentication state.
    var state: AuthenticationState

    /// Username associated with the session.
    var username: String?

    /// In-memory provider authentication token.
    var authToken: String?

    /// Provider server version reported during connection.
    var serverVersion: String?

    /// Date the session was created.
    var issuedAt: Date?

    /// Date the session should be considered expired.
    var expiresAt: Date?
}
