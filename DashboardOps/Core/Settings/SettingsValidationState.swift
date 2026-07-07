//
//  SettingsValidationState.swift
//  DashboardOps
//
//  Created by Codex on 7/7/26.
//

import Foundation

/// Lightweight validation state for configuration screens.
nonisolated enum SettingsValidationState: String, Codable, Sendable {
    case idle
    case valid
    case invalid
}
