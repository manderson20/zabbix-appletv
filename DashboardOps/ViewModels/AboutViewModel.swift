//
//  AboutViewModel.swift
//  DashboardOps
//
//  Created by Codex on 7/7/26.
//

import Combine
import Foundation

/// View model for the About screen.
@MainActor
final class AboutViewModel: ObservableObject {
    /// Application display name.
    let appName = "DashboardOps"

    /// User-facing app version.
    let version = AppVersion.marketingVersion

    /// App build number.
    let buildNumber = AppVersion.buildNumber

    /// Primary supported provider for Version 1.
    let primaryProvider = "Zabbix"
}
