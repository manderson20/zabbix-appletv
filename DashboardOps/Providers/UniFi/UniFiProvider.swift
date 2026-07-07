//
//  UniFiProvider.swift
//  DashboardOps
//
//  Created by Codex on 7/7/26.
//

import Foundation

/// Provider metadata reserved for a future UniFi integration.
nonisolated struct UniFiProvider: DashboardProvider {
    /// Stable provider identifier.
    let id = DashboardProviderKind.uniFi.rawValue

    /// Human-readable provider name.
    let displayName = "UniFi"

    /// Provider family.
    let kind = DashboardProviderKind.uniFi

    /// UniFi is planned for a later release.
    let supportStatus = ProviderSupportStatus.planned
}
