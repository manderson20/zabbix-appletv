//
//  ZabbixSessionService.swift
//  DashboardOps
//
//  Created by Codex on 7/7/26.
//

import Foundation

/// Coordinates Zabbix connection and session lifecycle.
actor ZabbixSessionService {
    private let apiClient: ZabbixAPIClient
    private let keychainService: KeychainService
    private let sessionManager: SessionManager
    private let settingsService: SettingsService

    /// Creates a Zabbix session service.
    init(
        settingsService: SettingsService,
        keychainService: KeychainService,
        apiClient: ZabbixAPIClient,
        sessionManager: SessionManager
    ) {
        self.settingsService = settingsService
        self.keychainService = keychainService
        self.apiClient = apiClient
        self.sessionManager = sessionManager
    }

    /// Connects to Zabbix using the saved server configuration and credential.
    func connect() async throws -> UserSession {
        let configuration = try await zabbixConfiguration()
        guard let serverBaseURL = configuration.baseURL else {
            throw DashboardOpsError.invalidServerURL
        }

        if let host = serverBaseURL.host {
            TLSTrustStore.shared.setTrustsSelfSignedCertificate(
                configuration.allowsSelfSignedCertificates,
                forHost: host
            )
        }

        guard let credentialIdentifier = configuration.credentialIdentifier,
              let password = try await keychainService.credential(for: credentialIdentifier),
              !password.isEmpty else {
            throw DashboardOpsError.missingCredential
        }

        let serverVersion = try await apiClient.apiVersion(serverBaseURL: serverBaseURL)
        let authToken = try await apiClient.login(
            serverBaseURL: serverBaseURL,
            username: configuration.username,
            password: password
        )

        let session = UserSession(
            id: UUID(),
            providerKind: .zabbix,
            serverConfigurationID: configuration.id,
            state: .signedIn,
            username: configuration.username,
            authToken: authToken,
            serverVersion: serverVersion,
            issuedAt: Date(),
            expiresAt: nil
        )

        await sessionManager.startSession(session)
        return session
    }

    /// Disconnects the active Zabbix session.
    func disconnect() async throws {
        guard let session = await sessionManager.activeSession(),
              session.providerKind == .zabbix,
              let authToken = session.authToken else {
            await sessionManager.endSession()
            return
        }

        if let configuration = try await settingsService.loadServerConfiguration(),
           let serverBaseURL = configuration.baseURL {
            _ = try await apiClient.logout(serverBaseURL: serverBaseURL, authToken: authToken)
        }

        await sessionManager.endSession()
    }

    /// Returns the active Zabbix session, if one is currently tracked.
    func activeSession() async -> UserSession? {
        await sessionManager.activeSession()
    }

    private func zabbixConfiguration() async throws -> ServerConfiguration {
        guard let configuration = try await settingsService.loadServerConfiguration(),
              configuration.providerKind == .zabbix else {
            throw DashboardOpsError.missingServerConfiguration
        }

        return configuration
    }
}
