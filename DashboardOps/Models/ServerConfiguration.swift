//
//  ServerConfiguration.swift
//  DashboardOps
//
//  Created by Codex on 7/7/26.
//

import Foundation

/// Stores connection settings for a provider server.
nonisolated struct ServerConfiguration: Identifiable, Codable, Equatable, Sendable {
    /// Stable local configuration identifier.
    let id: UUID

    /// Provider family this server belongs to.
    var providerKind: DashboardProviderKind

    /// Friendly name shown in settings.
    var name: String

    /// Base server URL used for API and dashboard requests.
    var baseURL: URL?

    /// Username used to authenticate with the provider.
    var username: String

    /// Keychain lookup key for the stored credential.
    var credentialIdentifier: String?

    /// Preferred dashboard for automatic playback.
    var preferredDashboardID: Dashboard.ID?

    /// Indicates whether self-signed or otherwise untrusted certificates may be allowed for this server's host.
    var allowsSelfSignedCertificates: Bool

    /// Number of seconds between dashboard refresh attempts.
    var refreshIntervalSeconds: TimeInterval
}
