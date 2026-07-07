//
//  SettingsViewModel.swift
//  DashboardOps
//
//  Created by Codex on 7/7/26.
//

import Combine
import Foundation

/// View model for the settings screen.
@MainActor
final class SettingsViewModel: ObservableObject {
    /// Provider cards displayed in settings.
    @Published private(set) var providers: [ProviderCardViewModel]

    /// Creates a settings view model from a provider registry.
    init(providerRegistry: ProviderRegistry) {
        providers = providerRegistry.providers.map { provider in
            ProviderCardViewModel(
                id: provider.id,
                name: provider.displayName,
                supportStatus: provider.supportStatus,
                isPrimary: provider.kind == .zabbix
            )
        }
    }
}
