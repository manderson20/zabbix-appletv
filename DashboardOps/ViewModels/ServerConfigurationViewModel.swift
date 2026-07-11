//
//  ServerConfigurationViewModel.swift
//  DashboardOps
//
//  Created by Codex on 7/7/26.
//

import Combine
import Foundation

/// View model for the Zabbix server configuration screen.
@MainActor
final class ServerConfigurationViewModel: ObservableObject {
    /// Friendly server name.
    @Published var displayName = "Zabbix"

    /// Server URL entered by the user.
    @Published var serverURL = ""

    /// Username reserved for future authentication.
    @Published var username = ""

    /// Password reserved for future authentication.
    @Published var password = ""

    /// Indicates whether self-signed certificates may be allowed.
    @Published var allowsSelfSignedCertificates = false

    /// Current validation state.
    @Published private(set) var validationState: SettingsValidationState = .idle

    /// Indicates whether a save operation is in progress.
    @Published private(set) var isSaving = false

    /// Human-readable status for configuration operations.
    @Published private(set) var statusMessage = ""

    private var configurationID = UUID()
    private var credentialIdentifier: String?
    private var hasLoaded = false
    private let keychainService: KeychainService
    private let settingsService: SettingsService

    /// Creates a server configuration view model.
    init(settingsService: SettingsService, keychainService: KeychainService) {
        self.settingsService = settingsService
        self.keychainService = keychainService
    }

    /// Indicates whether the current configuration can be saved.
    var canSave: Bool {
        normalizedServerURL != nil
    }

    /// Loads any saved configuration into editable fields.
    ///
    /// `hasLoaded` is only set once the attempt actually finishes, not before — the same
    /// cancel-during-a-view-transition risk `DashboardListViewModel.loadDashboards()` hit applies
    /// here too (this runs from a `.task` that can be recreated mid-flight), and marking it done
    /// before it truly is would leave the form permanently blank instead of retrying.
    func load() async {
        guard !hasLoaded else { return }

        do {
            guard let configuration = try await settingsService.loadServerConfiguration() else {
                hasLoaded = true
                return
            }

            configurationID = configuration.id
            displayName = configuration.name
            serverURL = configuration.baseURL?.absoluteString ?? ""
            username = configuration.username
            credentialIdentifier = configuration.credentialIdentifier
            allowsSelfSignedCertificates = configuration.allowsSelfSignedCertificates
            hasLoaded = true
        } catch {
            guard !Task.isCancelled else { return }
            validationState = .invalid
            statusMessage = "Saved configuration could not be loaded."
            hasLoaded = true
        }
    }

    /// Saves the current configuration.
    @discardableResult
    func save() async -> Bool {
        guard canSave else {
            validationState = .invalid
            statusMessage = "Enter a valid server URL."
            return false
        }

        isSaving = true
        defer { isSaving = false }

        let nextCredentialIdentifier = credentialIdentifier ?? "zabbix-\(configurationID.uuidString)"

        let configuration = ServerConfiguration(
            id: configurationID,
            providerKind: .zabbix,
            name: displayName.isEmpty ? "Zabbix" : displayName,
            baseURL: normalizedServerURL,
            username: username,
            credentialIdentifier: password.isEmpty ? credentialIdentifier : nextCredentialIdentifier,
            preferredDashboardID: nil,
            allowsSelfSignedCertificates: allowsSelfSignedCertificates,
            refreshIntervalSeconds: 60
        )

        do {
            if !password.isEmpty {
                try await keychainService.saveCredential(password, for: nextCredentialIdentifier)
                credentialIdentifier = nextCredentialIdentifier
                password = ""
            }

            try await settingsService.saveServerConfiguration(configuration)
            validationState = .valid
            statusMessage = "Configuration saved."
            return true
        } catch {
            validationState = .invalid
            statusMessage = "Configuration could not be saved."
            return false
        }
    }

    private var normalizedServerURL: URL? {
        let trimmedURL = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty else {
            return nil
        }

        if let url = URL(string: trimmedURL), url.scheme != nil {
            return url
        }

        return URL(string: "https://\(trimmedURL)")
    }
}
