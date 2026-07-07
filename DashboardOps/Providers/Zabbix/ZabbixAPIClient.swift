//
//  ZabbixAPIClient.swift
//  DashboardOps
//
//  Created by Codex on 7/7/26.
//

import Foundation

/// Performs typed JSON-RPC calls against the Zabbix API.
actor ZabbixAPIClient {
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private let networkService: NetworkService

    /// Creates a Zabbix API client.
    init(networkService: NetworkService) {
        self.networkService = networkService
        decoder = JSONDecoder()
        encoder = JSONEncoder()
    }

    /// Resolves the JSON-RPC endpoint for a Zabbix base URL.
    nonisolated static func apiURL(for baseURL: URL) -> URL {
        if baseURL.lastPathComponent == "api_jsonrpc.php" {
            return baseURL
        }

        return baseURL.appendingPathComponent("api_jsonrpc.php")
    }

    /// Resolves the Zabbix frontend root URL from a configured base URL.
    nonisolated static func frontendRootURL(for baseURL: URL) -> URL {
        if baseURL.lastPathComponent == "api_jsonrpc.php" {
            return baseURL.deletingLastPathComponent()
        }

        return baseURL
    }

    /// Resolves a kiosk-mode dashboard viewer URL for a dashboard identifier.
    ///
    /// This is descriptive metadata only (e.g. for sharing a link to view the dashboard in a real
    /// browser elsewhere) — tvOS has no in-app browser, so DashboardOps itself never loads this URL.
    nonisolated static func kioskDashboardURL(serverBaseURL: URL, dashboardID: String) -> URL {
        let dashboardPageURL = frontendRootURL(for: serverBaseURL).appendingPathComponent("zabbix.php")
        var components = URLComponents(url: dashboardPageURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "action", value: "dashboard.view"),
            URLQueryItem(name: "dashboardid", value: dashboardID),
            URLQueryItem(name: "kiosk", value: "1")
        ]

        return components?.url ?? dashboardPageURL
    }

    /// Fetches the Zabbix API version without authentication.
    func apiVersion(serverBaseURL: URL) async throws -> String {
        try await send(
            method: "apiinfo.version",
            params: ZabbixEmptyObjectParameters(),
            serverBaseURL: serverBaseURL,
            authToken: nil,
            resultType: String.self
        )
    }

    /// Logs into Zabbix and returns an authentication token.
    func login(serverBaseURL: URL, username: String, password: String) async throws -> String {
        try await send(
            method: "user.login",
            params: ZabbixLoginParameters(username: username, password: password),
            serverBaseURL: serverBaseURL,
            authToken: nil,
            resultType: String.self
        )
    }

    /// Logs out of Zabbix and invalidates the authentication token.
    func logout(serverBaseURL: URL, authToken: String) async throws -> Bool {
        try await send(
            method: "user.logout",
            params: [String](),
            serverBaseURL: serverBaseURL,
            authToken: authToken,
            resultType: Bool.self
        )
    }

    /// Fetches the dashboards visible to the authenticated user.
    func dashboards(serverBaseURL: URL, authToken: String) async throws -> [ZabbixDashboardSummary] {
        try await send(
            method: "dashboard.get",
            params: ZabbixDashboardGetParameters(),
            serverBaseURL: serverBaseURL,
            authToken: authToken,
            resultType: [ZabbixDashboardSummary].self
        )
    }

    /// Fetches a single dashboard's full widget layout.
    func dashboardDetail(serverBaseURL: URL, authToken: String, dashboardID: String) async throws -> ZabbixDashboardDetail {
        let dashboards = try await send(
            method: "dashboard.get",
            params: ZabbixDashboardGetDetailParameters(dashboardID: dashboardID),
            serverBaseURL: serverBaseURL,
            authToken: authToken,
            resultType: [ZabbixDashboardDetail].self
        )

        guard let dashboard = dashboards.first else {
            throw DashboardOpsError.invalidServerResponse
        }

        return dashboard
    }

    /// Fetches item metadata and last values for a set of item identifiers.
    func items(serverBaseURL: URL, authToken: String, itemIDs: [String]) async throws -> [ZabbixItemSummary] {
        try await send(
            method: "item.get",
            params: ZabbixItemGetParameters(itemIDs: itemIDs),
            serverBaseURL: serverBaseURL,
            authToken: authToken,
            resultType: [ZabbixItemSummary].self
        )
    }

    /// Fetches currently active problems, optionally filtered to a set of severities.
    func problems(serverBaseURL: URL, authToken: String, severities: [Int]? = nil) async throws -> [ZabbixProblemSummary] {
        try await send(
            method: "problem.get",
            params: ZabbixProblemGetParameters(severities: severities),
            serverBaseURL: serverBaseURL,
            authToken: authToken,
            resultType: [ZabbixProblemSummary].self
        )
    }

    /// Resolves the hosts a set of triggers belong to.
    func triggerHosts(serverBaseURL: URL, authToken: String, triggerIDs: [String]) async throws -> [ZabbixTriggerHosts] {
        guard !triggerIDs.isEmpty else {
            return []
        }

        return try await send(
            method: "trigger.get",
            params: ZabbixTriggerGetParameters(triggerIDs: triggerIDs),
            serverBaseURL: serverBaseURL,
            authToken: authToken,
            resultType: [ZabbixTriggerHosts].self
        )
    }

    private func send<Parameters, Result>(
        method: String,
        params: Parameters,
        serverBaseURL: URL,
        authToken: String?,
        resultType: Result.Type
    ) async throws -> Result where Parameters: Encodable & Sendable, Result: Decodable & Sendable {
        let apiRequest = ZabbixAPIRequest(method: method, params: params, id: 1)
        var urlRequest = URLRequest(url: Self.apiURL(for: serverBaseURL))
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = 30
        urlRequest.setValue("application/json-rpc", forHTTPHeaderField: "Content-Type")

        if let authToken {
            urlRequest.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        }

        urlRequest.httpBody = try encoder.encode(apiRequest)

        let data = try await networkService.data(for: urlRequest)
        let apiResponse = try decoder.decode(ZabbixAPIResponse<Result>.self, from: data)
        return try apiResponse.resolvedResult()
    }
}
