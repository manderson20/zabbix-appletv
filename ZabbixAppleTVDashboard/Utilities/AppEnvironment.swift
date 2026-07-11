//
//  AppEnvironment.swift
//  ZabbixAppleTVDashboard
//
//  Created by Codex on 7/7/26.
//

import Foundation

/// Dependency container for app-level services.
struct AppEnvironment: Sendable {
    /// Secure credential storage service.
    let keychainService: KeychainService

    /// Persistent settings service.
    let settingsService: SettingsService

    /// Network request service.
    let networkService: NetworkService

    /// Provider session service.
    let sessionManager: SessionManager

    /// Dashboard discovery and selection service.
    let dashboardManager: DashboardManager

    /// Zabbix JSON-RPC API client.
    let zabbixAPIClient: ZabbixAPIClient

    /// Zabbix session lifecycle service.
    let zabbixSessionService: ZabbixSessionService

    /// Creates the default application environment.
    init() {
        let keychainService = KeychainService()
        let settingsService = SettingsService()
        let networkService = NetworkService()
        let sessionManager = SessionManager()

        self.keychainService = keychainService
        self.settingsService = settingsService
        self.networkService = networkService
        self.sessionManager = sessionManager

        let zabbixAPIClient = ZabbixAPIClient(networkService: networkService)
        self.zabbixAPIClient = zabbixAPIClient
        zabbixSessionService = ZabbixSessionService(
            settingsService: settingsService,
            keychainService: keychainService,
            apiClient: zabbixAPIClient,
            sessionManager: sessionManager
        )
        dashboardManager = DashboardManager(
            settingsService: settingsService,
            zabbixAPIClient: zabbixAPIClient,
            zabbixSessionService: zabbixSessionService
        )
    }
}
