//
//  NetworkService.swift
//  DashboardOps
//
//  Created by Codex on 7/7/26.
//

import Foundation

/// Owns network requests and connectivity state.
actor NetworkService {
    /// Last known connectivity state.
    private(set) var connectionState: NetworkConnectionState = .idle

    private let session = URLSession(
        configuration: .default,
        delegate: DashboardOpsURLSessionDelegate(),
        delegateQueue: nil
    )

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
