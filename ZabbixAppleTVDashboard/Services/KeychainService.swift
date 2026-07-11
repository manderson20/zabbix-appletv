//
//  KeychainService.swift
//  ZabbixAppleTVDashboard
//
//  Created by Codex on 7/7/26.
//

import Foundation
import Security

/// Stores and retrieves sensitive provider credentials.
actor KeychainService {
    private let serviceName: String

    /// Creates a keychain service scoped to this application.
    init(serviceName: String = "org.brookfield.ZabbixAppleTVDashboard.credentials") {
        self.serviceName = serviceName
    }

    /// Saves a credential for a future provider authentication flow.
    func saveCredential(_ credential: String, for identifier: String) async throws {
        guard let credentialData = credential.data(using: .utf8) else {
            throw DashboardOpsError.credentialEncodingFailed
        }

        let query = baseQuery(for: identifier)
        let attributes: [String: Any] = [
            kSecValueData as String: credentialData,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var addQuery = query
            addQuery.merge(attributes) { _, newValue in newValue }
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw DashboardOpsError.secureStorageFailed(addStatus)
            }
        default:
            throw DashboardOpsError.secureStorageFailed(updateStatus)
        }
    }

    /// Loads a credential for a future provider authentication flow.
    func credential(for identifier: String) async throws -> String? {
        var query = baseQuery(for: identifier)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let data = result as? Data else {
                throw DashboardOpsError.secureStorageFailed(status)
            }

            return String(data: data, encoding: .utf8)
        case errSecItemNotFound:
            return nil
        default:
            throw DashboardOpsError.secureStorageFailed(status)
        }
    }

    /// Deletes a stored credential.
    func deleteCredential(for identifier: String) async throws {
        let status = SecItemDelete(baseQuery(for: identifier) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw DashboardOpsError.secureStorageFailed(status)
        }
    }

    private func baseQuery(for identifier: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: identifier
        ]
    }
}
