//
//  DashboardOpsURLSessionDelegate.swift
//  DashboardOps
//
//  Created by Codex on 7/7/26.
//

import Foundation

/// Trusts self-signed certificates for hosts explicitly allowed via `TLSTrustStore`.
nonisolated final class DashboardOpsURLSessionDelegate: NSObject, URLSessionDelegate {
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust,
              TLSTrustStore.shared.trustsSelfSignedCertificate(forHost: challenge.protectionSpace.host) else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        completionHandler(.useCredential, URLCredential(trust: serverTrust))
    }
}
