//
//  ProviderCardViewModel.swift
//  DashboardOps
//
//  Created by Codex on 7/7/26.
//

import Foundation

/// Display metadata for provider status cards.
struct ProviderCardViewModel: Identifiable, Hashable, Sendable {
    /// Stable provider identifier.
    let id: String

    /// Provider display name.
    let name: String

    /// Release support status.
    let supportStatus: ProviderSupportStatus

    /// Indicates whether this provider is the Phase 1 target.
    let isPrimary: Bool
}
