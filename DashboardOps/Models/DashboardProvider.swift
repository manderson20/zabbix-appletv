//
//  DashboardProvider.swift
//  DashboardOps
//
//  Created by Codex on 7/7/26.
//

import Foundation

/// Defines the metadata every dashboard provider exposes to the app shell.
nonisolated protocol DashboardProvider: Sendable {
    /// Stable provider identifier.
    var id: String { get }

    /// Human-readable provider name.
    var displayName: String { get }

    /// Provider family used by settings, sessions, and dashboards.
    var kind: DashboardProviderKind { get }

    /// Current product support state for the provider.
    var supportStatus: ProviderSupportStatus { get }
}
