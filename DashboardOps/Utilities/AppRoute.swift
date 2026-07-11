//
//  AppRoute.swift
//  DashboardOps
//
//  Created by Codex on 7/7/26.
//

import Foundation

/// Destinations pushed on top of the app's root screen (Server Configuration or Dashboard List,
/// whichever `RootViewModel.hasConfiguration` selects — neither is a pushable route itself).
enum AppRoute: Hashable {
    case serverConfiguration
    case dashboardViewer
}
