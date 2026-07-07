//
//  BuslineProvider.swift
//  DashboardOps
//
//  Created by Codex on 7/7/26.
//

import Foundation

/// Provider metadata reserved for a future Busline integration.
nonisolated struct BuslineProvider: DashboardProvider {
    /// Stable provider identifier.
    let id = DashboardProviderKind.busline.rawValue

    /// Human-readable provider name.
    let displayName = "Busline"

    /// Provider family.
    let kind = DashboardProviderKind.busline

    /// Busline is planned for a later release.
    let supportStatus = ProviderSupportStatus.planned
}
