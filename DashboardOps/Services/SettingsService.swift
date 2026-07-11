//
//  SettingsService.swift
//  DashboardOps
//
//  Created by Codex on 7/7/26.
//

import Foundation

/// Persists app settings and provider configuration.
actor SettingsService {
    private enum SettingsKey {
        static let serverConfiguration = "dashboardops.serverConfiguration"
        static let displaySettings = "dashboardops.displaySettings"
    }

    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    // `UserDefaults` is itself thread-safe, so reading through it doesn't need actor isolation —
    // this lets `hasServerConfiguration()` answer synchronously, with no `await` gap at all, for
    // the app's very first frame to decide which screen to show with no loading screen in between.
    nonisolated(unsafe) private let userDefaults: UserDefaults

    /// Creates a settings service backed by a user defaults store.
    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        decoder = JSONDecoder()
        encoder = JSONEncoder()
    }

    /// Whether a server configuration is already saved — checked synchronously so the app's root
    /// view can be decided before the very first frame renders.
    nonisolated func hasServerConfiguration() -> Bool {
        userDefaults.data(forKey: SettingsKey.serverConfiguration) != nil
    }

    /// Loads the saved server configuration.
    func loadServerConfiguration() async throws -> ServerConfiguration? {
        try load(ServerConfiguration.self, forKey: SettingsKey.serverConfiguration)
    }

    /// Saves the selected server configuration.
    func saveServerConfiguration(_ configuration: ServerConfiguration) async throws {
        try save(configuration, forKey: SettingsKey.serverConfiguration)
    }

    /// Loads dashboard display settings.
    func loadDisplaySettings() async throws -> DashboardDisplaySettings? {
        try load(DashboardDisplaySettings.self, forKey: SettingsKey.displaySettings)
    }

    /// Saves dashboard display settings.
    func saveDisplaySettings(_ settings: DashboardDisplaySettings) async throws {
        try save(settings, forKey: SettingsKey.displaySettings)
    }

    /// Removes all persisted settings.
    func reset() async {
        userDefaults.removeObject(forKey: SettingsKey.serverConfiguration)
        userDefaults.removeObject(forKey: SettingsKey.displaySettings)
    }

    private func load<Value: Decodable>(_ type: Value.Type, forKey key: String) throws -> Value? {
        guard let data = userDefaults.data(forKey: key) else {
            return nil
        }

        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw DashboardOpsError.settingsDecodingFailed
        }
    }

    private func save<Value: Encodable>(_ value: Value, forKey key: String) throws {
        do {
            let data = try encoder.encode(value)
            userDefaults.set(data, forKey: key)
        } catch {
            throw DashboardOpsError.settingsEncodingFailed
        }
    }
}
