//
//  SplashViewModel.swift
//  DashboardOps
//
//  Created by Codex on 7/7/26.
//

import Combine
import Foundation

/// View model for the launch splash screen — shown only for the moment it takes to check for a
/// saved server configuration, so there's no "ready" state to report: by the time that check
/// finishes, `RootViewModel` has already navigated away.
@MainActor
final class SplashViewModel: ObservableObject {
    /// Current startup status message.
    @Published private(set) var statusMessage = "Starting DashboardOps"

    /// Prepares the app shell for navigation.
    func prepareLaunch() async {
        statusMessage = "Checking saved configuration"
    }
}
