//
//  TLSTrustStore.swift
//  ZabbixAppleTVDashboard
//
//  Created by Codex on 7/7/26.
//

import Foundation

/// Thread-safe registry of hosts explicitly allowed to present self-signed or otherwise untrusted certificates.
///
/// Consulted synchronously from `URLSessionDelegate` and `WKNavigationDelegate` authentication
/// challenge callbacks, which are not guaranteed to run on the main actor, so this type opts out
/// of the module's default main-actor isolation.
nonisolated final class TLSTrustStore: @unchecked Sendable {
    /// Shared instance used by the app's URL session and dashboard web view.
    static let shared = TLSTrustStore()

    private let lock = NSLock()
    private var trustedHosts: Set<String> = []

    private init() {}

    /// Sets whether a host's self-signed or untrusted certificate should be trusted.
    func setTrustsSelfSignedCertificate(_ trusts: Bool, forHost host: String) {
        lock.lock()
        defer { lock.unlock() }

        if trusts {
            trustedHosts.insert(host)
        } else {
            trustedHosts.remove(host)
        }
    }

    /// Returns whether a host's self-signed or untrusted certificate should be trusted.
    func trustsSelfSignedCertificate(forHost host: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        return trustedHosts.contains(host)
    }
}
