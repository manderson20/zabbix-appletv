//
//  SplashViewModel.swift
//  DashboardOps
//
//  Created by Codex on 7/7/26.
//

import Combine
import Foundation

/// View model for the launch splash screen.
@MainActor
final class SplashViewModel: ObservableObject {
    /// Current startup status message.
    @Published private(set) var statusMessage = "Starting DashboardOps"

    /// Indicates whether startup preparation is active.
    @Published private(set) var isPreparing = false

    /// Prepares the app shell for navigation.
    func prepareLaunch() async {
        guard !isPreparing else { return }
        isPreparing = true
        statusMessage = "Checking saved configuration"
        try? await Task.sleep(nanoseconds: 350_000_000)
        statusMessage = "Ready"
        isPreparing = false
    }
}
