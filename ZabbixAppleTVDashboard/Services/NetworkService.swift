//
//  NetworkService.swift
//  ZabbixAppleTVDashboard
//
//  Created by Codex on 7/7/26.
//

import Foundation

/// Owns network requests and connectivity state.
actor NetworkService {
    /// Last known connectivity state.
    private(set) var connectionState: NetworkConnectionState = .idle

    private let session = URLSession(
        configuration: NetworkService.monitoringConfiguration,
        delegate: DashboardOpsURLSessionDelegate(),
        delegateQueue: nil
    )

    /// URLSession configuration tuned for a monitoring client that must always show current data
    /// and runs unattended for days.
    ///
    /// The stock `.default` configuration keeps an on-disk HTTP cache (the `Cache.db` that grows in
    /// the app's Caches directory). For a dashboard that re-polls the same JSON-RPC endpoints every
    /// few seconds around the clock that is wrong twice over: a cache hit could paint stale
    /// monitoring data, and the cache store churns disk and holds an in-memory index that only
    /// grows the longer the app stays up. Auth is a token carried in each request body, not a
    /// cookie or stored credential, so there is nothing to persist between launches — an ephemeral
    /// configuration with caching switched off entirely fits exactly, and keeps the process
    /// footprint flat over a multi-day run.
    private static var monitoringConfiguration: URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return configuration
    }

    /// Performs a network request and returns the response body.
    func data(for request: URLRequest) async throws -> Data {
        connectionState = .checking

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                connectionState = .unreachable
                throw DashboardOpsError.invalidServerResponse
            }

            guard 200..<300 ~= httpResponse.statusCode else {
                connectionState = .unreachable
                throw DashboardOpsError.networkRequestFailed(httpResponse.statusCode)
            }

            connectionState = .reachable
            return data
        } catch {
            connectionState = .unreachable
            throw error
        }
    }

    /// Returns the last known connectivity status.
    func updateConnectionState() async -> NetworkConnectionState {
        connectionState
    }
}
