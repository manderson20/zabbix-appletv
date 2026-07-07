//
//  AppVersion.swift
//  DashboardOps
//
//  Created by Codex on 7/7/26.
//

import Foundation

/// Reads displayable app version metadata.
enum AppVersion {
    /// Version shown when bundle metadata is unavailable.
    static let fallbackMarketingVersion = "0.1.0"

    /// User-facing app version.
    static var marketingVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? fallbackMarketingVersion
    }

    /// Build number shown in About.
    static var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
}
