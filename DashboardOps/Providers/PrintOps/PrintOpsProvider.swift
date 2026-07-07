//
//  PrintOpsProvider.swift
//  DashboardOps
//
//  Created by Codex on 7/7/26.
//

import Foundation

/// Provider metadata reserved for a future PrintOps integration.
nonisolated struct PrintOpsProvider: DashboardProvider {
    /// Stable provider identifier.
    let id = DashboardProviderKind.printOps.rawValue

    /// Human-readable provider name.
    let displayName = "PrintOps"

    /// Provider family.
    let kind = DashboardProviderKind.printOps

    /// PrintOps is planned for a later release.
    let supportStatus = ProviderSupportStatus.planned
}
