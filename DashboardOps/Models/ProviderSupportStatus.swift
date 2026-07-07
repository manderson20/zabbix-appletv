//
//  ProviderSupportStatus.swift
//  DashboardOps
//
//  Created by Codex on 7/7/26.
//

import Foundation

/// Describes whether a dashboard provider is available in the current release.
nonisolated enum ProviderSupportStatus: String, Codable, Sendable {
    case supported
    case planned
}
