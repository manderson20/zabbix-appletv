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

    /// Fetches enabled hosts with their monitoring interfaces, for the "hostavail" widget.
    func hostsWithInterfaces(serverBaseURL: URL, authToken: String) async throws -> [ZabbixHostAvailability] {
        try await send(
            method: "host.get",
            params: ZabbixHostAvailabilityParameters(),
            serverBaseURL: serverBaseURL,
            authToken: authToken,
            resultType: [ZabbixHostAvailability].self
        )
    }

    /// Counts enabled hosts.
    func hostCount(serverBaseURL: URL, authToken: String) async throws -> Int {
        let count = try await send(
            method: "host.get",
            params: ZabbixHostCountParameters(),
            serverBaseURL: serverBaseURL,
            authToken: authToken,
            resultType: String.self
        )
        return Int(count) ?? 0
    }

    /// Counts enabled items.
    func itemCount(serverBaseURL: URL, authToken: String) async throws -> Int {
        let count = try await send(
            method: "item.get",
            params: ZabbixItemCountParameters(),
            serverBaseURL: serverBaseURL,
            authToken: authToken,
            resultType: String.self
        )
        return Int(count) ?? 0
    }

    /// Counts currently active problems.
    func problemCount(serverBaseURL: URL, authToken: String) async throws -> Int {
        let count = try await send(
            method: "problem.get",
            params: ZabbixProblemCountParameters(),
            serverBaseURL: serverBaseURL,
            authToken: authToken,
            resultType: String.self
        )
        return Int(count) ?? 0
    }

    /// Fetches triggers currently in the PROBLEM state, with their hosts.
    func activeTriggers(
        serverBaseURL: URL,
        authToken: String,
        groupIDs: [String]? = nil,
        hostIDs: [String]? = nil,
        limit: Int = 100
    ) async throws -> [ZabbixTriggerSummary] {
        try await send(
            method: "trigger.get",
            params: ZabbixActiveTriggerGetParameters(groupids: groupIDs, hostids: hostIDs, limit: limit),
            serverBaseURL: serverBaseURL,
            authToken: authToken,
            resultType: [ZabbixTriggerSummary].self
        )
    }

    /// Resolves the host groups a set of hosts belong to.
    func hostGroups(serverBaseURL: URL, authToken: String, hostIDs: [String]) async throws -> [ZabbixHostGroupLookup] {
        guard !hostIDs.isEmpty else {
            return []
        }

        return try await send(
            method: "host.get",
            params: ZabbixHostGroupLookupParameters(hostIDs: hostIDs),
            serverBaseURL: serverBaseURL,
            authToken: authToken,
            resultType: [ZabbixHostGroupLookup].self
        )
    }

    /// Searches items by name pattern, with their owning host, for host/group-scoped item widgets.
    func itemsMatching(
        serverBaseURL: URL,
        authToken: String,
        groupIDs: [String]? = nil,
        hostIDs: [String]? = nil,
        namePattern: String? = nil
    ) async throws -> [ZabbixItemWithHost] {
        try await send(
            method: "item.get",
            params: ZabbixItemSearchParameters(groupIDs: groupIDs, hostIDs: hostIDs, namePattern: namePattern),
            serverBaseURL: serverBaseURL,
            authToken: authToken,
            resultType: [ZabbixItemWithHost].self
        )
    }

    /// Fetches an item's most recent historical values.
    func history(
        serverBaseURL: URL,
        authToken: String,
        itemID: String,
        historyValueType: Int,
        sinceUnixTime: Int,
        limit: Int = 100
    ) async throws -> [ZabbixHistoryValue] {
        try await send(
            method: "history.get",
            params: ZabbixHistoryGetParameters(
                historyValueType: historyValueType,
                itemIDs: [itemID],
                sinceUnixTime: sinceUnixTime,
                limit: limit
            ),
            serverBaseURL: serverBaseURL,
            authToken: authToken,
            resultType: [ZabbixHistoryValue].self
        )
    }

    /// Fetches recent notifications and remote commands since a given time.
    func alerts(serverBaseURL: URL, authToken: String, sinceUnixTime: Int) async throws -> [ZabbixAlert] {
        try await send(
            method: "alert.get",
            params: ZabbixAlertGetParameters(sinceUnixTime: sinceUnixTime),
            serverBaseURL: serverBaseURL,
            authToken: authToken,
            resultType: [ZabbixAlert].self
        )
    }

    /// Fetches network discovery rules.
    func discoveryRules(serverBaseURL: URL, authToken: String) async throws -> [ZabbixDiscoveryRule] {
        try await send(
            method: "drule.get",
            params: ZabbixDiscoveryRuleGetParameters(),
            serverBaseURL: serverBaseURL,
            authToken: authToken,
            resultType: [ZabbixDiscoveryRule].self
        )
    }

    /// Fetches hosts discovered by a set of discovery rules, for status tallying.
    func discoveredHosts(serverBaseURL: URL, authToken: String, ruleIDs: [String]) async throws -> [ZabbixDiscoveredHost] {
        guard !ruleIDs.isEmpty else {
            return []
        }

        return try await send(
            method: "dhost.get",
            params: ZabbixDiscoveredHostGetParameters(druleIDs: ruleIDs),
            serverBaseURL: serverBaseURL,
            authToken: authToken,
            resultType: [ZabbixDiscoveredHost].self
        )
    }

    /// Fetches web monitoring scenarios with their hosts.
    func webScenarios(
        serverBaseURL: URL,
        authToken: String,
        groupIDs: [String]? = nil,
        hostIDs: [String]? = nil
    ) async throws -> [ZabbixWebScenario] {
        try await send(
            method: "httptest.get",
            params: ZabbixWebScenarioGetParameters(groupIDs: groupIDs, hostIDs: hostIDs),
            serverBaseURL: serverBaseURL,
            authToken: authToken,
            resultType: [ZabbixWebScenario].self
        )
    }

    /// Lists enabled hosts by group and/or host filter.
    func hosts(
        serverBaseURL: URL,
        authToken: String,
        groupIDs: [String]? = nil,
        hostIDs: [String]? = nil
    ) async throws -> [ZabbixHostListEntry] {
        try await send(
            method: "host.get",
            params: ZabbixHostListParameters(groupIDs: groupIDs, hostIDs: hostIDs),
            serverBaseURL: serverBaseURL,
            authToken: authToken,
            resultType: [ZabbixHostListEntry].self
        )
    }

    /// Resolves hosts by their exact technical name.
    func hostsByName(serverBaseURL: URL, authToken: String, names: [String]) async throws -> [ZabbixHostListEntry] {
        guard !names.isEmpty else {
            return []
        }

        return try await send(
            method: "host.get",
            params: ZabbixHostByNameParameters(names: names),
            serverBaseURL: serverBaseURL,
            authToken: authToken,
            resultType: [ZabbixHostListEntry].self
        )
    }

    /// Resolves a classic Graph object's member items.
    func graphs(serverBaseURL: URL, authToken: String, graphIDs: [String]) async throws -> [ZabbixGraphDefinition] {
        guard !graphIDs.isEmpty else {
            return []
        }

        return try await send(
            method: "graph.get",
            params: ZabbixGraphGetParameters(graphIDs: graphIDs),
            serverBaseURL: serverBaseURL,
            authToken: authToken,
            resultType: [ZabbixGraphDefinition].self
        )
    }

    /// Fetches hosts with their inventory location fields, for the geomap widget.
    func hostsWithInventory(
        serverBaseURL: URL,
        authToken: String,
        groupIDs: [String]? = nil,
        hostIDs: [String]? = nil
    ) async throws -> [ZabbixHostWithInventory] {
        try await send(
            method: "host.get",
            params: ZabbixHostInventoryParameters(groupIDs: groupIDs, hostIDs: hostIDs),
            serverBaseURL: serverBaseURL,
            authToken: authToken,
            resultType: [ZabbixHostWithInventory].self
        )
    }

    /// Lists available network maps by name.
    func maps(serverBaseURL: URL, authToken: String) async throws -> [ZabbixMapSummary] {
        try await send(
            method: "map.get",
            params: ZabbixMapListParameters(),
            serverBaseURL: serverBaseURL,
            authToken: authToken,
            resultType: [ZabbixMapSummary].self
        )
    }

    /// Fetches a single network map's full topology (elements and links).
    func networkMap(serverBaseURL: URL, authToken: String, mapID: String) async throws -> ZabbixNetworkMap? {
        let maps = try await send(
            method: "map.get",
            params: ZabbixNetworkMapGetParameters(mapID: mapID),
            serverBaseURL: serverBaseURL,
            authToken: authToken,
            resultType: [ZabbixNetworkMap].self
        )
        return maps.first
    }

    /// Fetches SLA definitions.
    func slas(serverBaseURL: URL, authToken: String, slaIDs: [String]? = nil) async throws -> [ZabbixSLA] {
        try await send(
            method: "sla.get",
            params: ZabbixSLAGetParameters(slaIDs: slaIDs),
            serverBaseURL: serverBaseURL,
            authToken: authToken,
            resultType: [ZabbixSLA].self
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
