//
//  NetworkConnectionState.swift
//  DashboardOps
//
//  Created by Codex on 7/7/26.
//

import Foundation

/// High-level network state reserved for future connectivity checks.
nonisolated enum NetworkConnectionState: String, Codable, Sendable {
    case idle
    case checking
    case reachable
    case unreachable
}
