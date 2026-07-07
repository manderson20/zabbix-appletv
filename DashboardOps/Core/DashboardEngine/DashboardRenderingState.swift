//
//  DashboardRenderingState.swift
//  DashboardOps
//
//  Created by Codex on 7/7/26.
//

import Foundation

/// High-level rendering state for the dashboard viewer.
nonisolated enum DashboardRenderingState: String, Codable, Sendable {
    case idle
    case loading
    case ready
    case unavailable
}
