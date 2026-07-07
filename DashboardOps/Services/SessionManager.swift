//
//  SessionManager.swift
//  DashboardOps
//
//  Created by Codex on 7/7/26.
//

import Foundation

/// Coordinates in-memory provider sessions.
actor SessionManager {
    /// Current in-memory session, if one exists.
    private(set) var currentSession: UserSession?

    /// Returns the currently tracked provider session.
    func activeSession() async -> UserSession? {
        currentSession
    }

    /// Starts tracking a provider session.
    func startSession(_ session: UserSession) async {
        currentSession = session
    }

    /// Ends the current provider session.
    func endSession() async {
        currentSession = nil
    }
}
