//
//  ZabbixAppleTVDashboardTests.swift
//  ZabbixAppleTVDashboardTests
//
//  Created by Mathew Anderson on 7/7/26.
//

import Testing
import Foundation
@testable import ZabbixAppleTVDashboard

struct ZabbixAppleTVDashboardTests {

    @Test func settingsServicePersistsServerConfiguration() async throws {
        let suiteName = "ZabbixAppleTVDashboardTests.\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        let service = SettingsService(userDefaults: userDefaults)
        let configuration = ServerConfiguration(
            id: UUID(),
            providerKind: .zabbix,
            name: "Zabbix Production",
            baseURL: URL(string: "https://zabbix.example.org"),
            username: "viewer",
            credentialIdentifier: "credential-id",
            preferredDashboardID: nil,
            allowsSelfSignedCertificates: false,
            refreshIntervalSeconds: 60
        )

        try await service.saveServerConfiguration(configuration)

        let loadedConfiguration = try await service.loadServerConfiguration()
        #expect(loadedConfiguration == configuration)
    }

    @Test func zabbixAPIClientBuildsJSONRPCEndpoint() throws {
        let baseURL = try #require(URL(string: "https://zabbix.example.org/zabbix"))
        let apiURL = ZabbixAPIClient.apiURL(for: baseURL)

        #expect(apiURL.absoluteString == "https://zabbix.example.org/zabbix/api_jsonrpc.php")
    }

    @Test func zabbixAPIResponseReturnsAPIError() throws {
        let responseData = try #require(
            """
            {
              "jsonrpc": "2.0",
              "error": {
                "code": -32602,
                "message": "Invalid params.",
                "data": "Login name or password is incorrect."
              },
              "id": 1
            }
            """.data(using: .utf8)
        )

        let response = try JSONDecoder().decode(ZabbixAPIResponse<String>.self, from: responseData)
        var didThrowAPIError = false

        do {
            _ = try response.resolvedResult()
        } catch let error as ZabbixAPIError {
            didThrowAPIError = true
            #expect(error.code == -32602)
            #expect(error.message == "Invalid params.")
        }

        #expect(didThrowAPIError)
    }

    @Test func zabbixAPIResponseDecodesDashboardList() throws {
        let responseData = try #require(
            """
            {
              "jsonrpc": "2.0",
              "result": [
                { "dashboardid": "1", "name": "Network Overview" },
                { "dashboardid": "2", "name": "Server Health" }
              ],
              "id": 1
            }
            """.data(using: .utf8)
        )

        let response = try JSONDecoder().decode(ZabbixAPIResponse<[ZabbixDashboardSummary]>.self, from: responseData)
        let dashboards = try response.resolvedResult()

        #expect(dashboards.count == 2)
        #expect(dashboards[0].dashboardid == "1")
        #expect(dashboards[1].name == "Server Health")
    }

    @Test func zabbixAPIClientBuildsKioskDashboardURL() throws {
        let baseURL = try #require(URL(string: "https://zabbix.example.org/zabbix"))

        let kioskURL = ZabbixAPIClient.kioskDashboardURL(serverBaseURL: baseURL, dashboardID: "7")
        let components = try #require(URLComponents(url: kioskURL, resolvingAgainstBaseURL: false))
        #expect(components.path == "/zabbix/zabbix.php")
        let queryItems = try #require(components.queryItems)
        #expect(queryItems.contains(URLQueryItem(name: "action", value: "dashboard.view")))
        #expect(queryItems.contains(URLQueryItem(name: "dashboardid", value: "7")))
        #expect(queryItems.contains(URLQueryItem(name: "kiosk", value: "1")))
    }

    @Test func dashboardIdentifierIsStableAcrossFetches() throws {
        func makeDashboard() -> Dashboard {
            Dashboard(
                providerKind: .zabbix,
                providerDashboardID: "7",
                title: "Network Overview",
                subtitle: nil,
                url: nil,
                displaySettings: .standard,
                isDefault: true
            )
        }

        #expect(makeDashboard().id == makeDashboard().id)
    }

    @Test func tlsTrustStoreTracksHostsIndependently() throws {
        let store = TLSTrustStore.shared
        let host = "trust-test-\(UUID().uuidString).example.org"

        #expect(store.trustsSelfSignedCertificate(forHost: host) == false)

        store.setTrustsSelfSignedCertificate(true, forHost: host)
        #expect(store.trustsSelfSignedCertificate(forHost: host) == true)

        store.setTrustsSelfSignedCertificate(false, forHost: host)
        #expect(store.trustsSelfSignedCertificate(forHost: host) == false)
    }

    @Test func numericStringDecodesBothNumbersAndStrings() throws {
        let numberData = try #require("42".data(using: .utf8))
        let stringData = try #require("\"42\"".data(using: .utf8))

        let fromNumber = try JSONDecoder().decode(ZabbixNumericString.self, from: numberData)
        let fromString = try JSONDecoder().decode(ZabbixNumericString.self, from: stringData)

        #expect(fromNumber.intValue == 42)
        #expect(fromString.intValue == 42)
    }

    @Test func zabbixAPIResponseDecodesDashboardDetailWidgets() throws {
        let responseData = try #require(
            """
            {
              "jsonrpc": "2.0",
              "result": [
                {
                  "dashboardid": "1",
                  "name": "Network Overview",
                  "pages": [
                    {
                      "name": "",
                      "widgets": [
                        {
                          "widgetid": "10",
                          "type": "clock",
                          "name": "",
                          "x": "0",
                          "y": 0,
                          "width": "4",
                          "height": "2",
                          "fields": []
                        },
                        {
                          "widgetid": "11",
                          "type": "item",
                          "name": "CPU Load",
                          "x": "4",
                          "y": "0",
                          "width": "4",
                          "height": "2",
                          "fields": [
                            { "name": "itemid.0", "value": "5001" }
                          ]
                        }
                      ]
                    }
                  ]
                }
              ],
              "id": 1
            }
            """.data(using: .utf8)
        )

        let response = try JSONDecoder().decode(ZabbixAPIResponse<[ZabbixDashboardDetail]>.self, from: responseData)
        let dashboards = try response.resolvedResult()
        let widgets = try #require(dashboards.first?.pages.first?.widgets)

        #expect(widgets.count == 2)
        #expect(widgets[0].type == "clock")
        #expect(widgets[0].width.intValue == 4)
        #expect(widgets[1].fields.first?.value == "5001")
    }

    @Test @MainActor func dashboardWidgetGridComputesExtentFromWidgets() throws {
        let widgets = [
            RenderableDashboardWidget(
                id: "1",
                title: "Clock",
                frame: DashboardWidgetFrame(x: 0, y: 0, width: 4, height: 2),
                refreshIntervalSeconds: 60,
                hasHiddenHeader: false,
                kind: .clock(ClockConfiguration(style: .analog, timeZoneIdentifier: nil, hostTimeOffset: nil))
            ),
            RenderableDashboardWidget(
                id: "2",
                title: "CPU Load",
                frame: DashboardWidgetFrame(x: 4, y: 0, width: 8, height: 4),
                refreshIntervalSeconds: 30,
                hasHiddenHeader: false,
                kind: .itemValue(name: "CPU Load", value: "0.42", units: "", decimalPlaces: 2, backgroundColorHex: nil, trend: nil, lastUpdated: nil, mappedText: nil)
            )
        ]

        let extent = DashboardWidgetGridView.gridExtent(for: widgets)

        #expect(extent.columns == 12)
        #expect(extent.rows == 4)
    }

    @Test func zabbixAPIResponseDecodesProblemsWithoutSelectHosts() throws {
        // problem.get does not support selectHosts (verified against a live Zabbix 7.0 server);
        // host names are resolved separately via trigger.get using objectid.
        let responseData = try #require(
            """
            {
              "jsonrpc": "2.0",
              "result": [
                { "eventid": "244184912", "name": "GPU appears idle for too long:", "severity": "4", "clock": "1783462230", "objectid": "58189" }
              ],
              "id": 1
            }
            """.data(using: .utf8)
        )

        let response = try JSONDecoder().decode(ZabbixAPIResponse<[ZabbixProblemSummary]>.self, from: responseData)
        let problems = try response.resolvedResult()

        #expect(problems.count == 1)
        #expect(problems[0].objectid == "58189")
        #expect(problems[0].severity.intValue == 4)
    }

    @Test func zabbixAPIResponseDecodesTriggerHosts() throws {
        let responseData = try #require(
            """
            {
              "jsonrpc": "2.0",
              "result": [
                { "triggerid": "58189", "hosts": [ { "hostid": "11434", "name": "Bruno-1" } ] }
              ],
              "id": 1
            }
            """.data(using: .utf8)
        )

        let response = try JSONDecoder().decode(ZabbixAPIResponse<[ZabbixTriggerHosts]>.self, from: responseData)
        let triggerHosts = try response.resolvedResult()

        #expect(triggerHosts.first?.hosts.first?.name == "Bruno-1")
    }

    @Test func zabbixAPIResponseDecodesHostInterfaces() throws {
        let responseData = try #require(
            """
            {
              "jsonrpc": "2.0",
              "result": [
                { "hostid": "10359", "interfaces": [ { "type": "1", "available": "0" }, { "type": "2", "available": "1" } ] }
              ],
              "id": 1
            }
            """.data(using: .utf8)
        )

        let response = try JSONDecoder().decode(ZabbixAPIResponse<[ZabbixHostAvailability]>.self, from: responseData)
        let hosts = try response.resolvedResult()

        #expect(hosts.first?.interfaces.count == 2)
        #expect(hosts.first?.interfaces[1].type.intValue == 2)
        #expect(hosts.first?.interfaces[1].available.intValue == 1)
    }

    @Test func zabbixAPIResponseParsesCountOutputAsInt() throws {
        let responseData = try #require(
            """
            { "jsonrpc": "2.0", "result": "912", "id": 1 }
            """.data(using: .utf8)
        )

        let response = try JSONDecoder().decode(ZabbixAPIResponse<String>.self, from: responseData)
        let count = try response.resolvedResult()

        #expect(Int(count) == 912)
    }

    @Test func widgetFieldHelpersParseScalarAndIndexedFields() throws {
        let fields = [
            ZabbixWidgetField(name: "min", value: "0"),
            ZabbixWidgetField(name: "groupids.0", value: "10"),
            ZabbixWidgetField(name: "groupids.1", value: "20"),
            ZabbixWidgetField(name: "itemid.0", value: "155071")
        ]

        #expect(DashboardManager.fieldValue(fields, name: "min") == "0")
        #expect(DashboardManager.indexedValues(fields, name: "groupids") == ["10", "20"])
        #expect(DashboardManager.firstIndexedValue(fields, name: "itemid") == "155071")
        #expect(DashboardManager.firstIndexedValue(fields, name: "hostid") == nil)
    }

    @Test func widgetFieldHelpersGroupIndexedFieldsByPrefix() throws {
        let fields = [
            ZabbixWidgetField(name: "thresholds.0.threshold", value: "50"),
            ZabbixWidgetField(name: "thresholds.0.color", value: "FF0000"),
            ZabbixWidgetField(name: "thresholds.1.threshold", value: "80"),
            ZabbixWidgetField(name: "thresholds.1.color", value: "00FF00")
        ]

        let groups = DashboardManager.indexedFieldGroups(fields, prefix: "thresholds")

        #expect(groups.count == 2)
        #expect(groups[0]["threshold"] == "50")
        #expect(groups[0]["color"] == "FF0000")
        #expect(groups[1]["threshold"] == "80")
    }

    @Test func rankTopHostsRowsOrdersByColumnAndLimits() throws {
        let scored: [(row: String, sortValue: Double?)] = [
            (row: "web1", sortValue: 40),
            (row: "web2", sortValue: 95),
            (row: "web3", sortValue: 12),
            (row: "web4", sortValue: nil) // no data in the ranking column
        ]

        // Top-N: highest first, unscored last, limited to 2.
        let top = DashboardManager.rankTopHostsRows(scored, isBottomN: false, limit: 2)
        #expect(top == ["web2", "web1"])

        // Bottom-N: lowest first, unscored still last.
        let bottom = DashboardManager.rankTopHostsRows(scored, isBottomN: true, limit: 4)
        #expect(bottom == ["web3", "web1", "web2", "web4"])
    }

    @Test func zabbixAPIResponseDecodesHostGroupLookupPluralKey() throws {
        // host.get's selectHostGroups response key is "hostgroups" (verified against a live
        // Zabbix 7.0 server), not "hostGroups" or "groups".
        let responseData = try #require(
            """
            {
              "jsonrpc": "2.0",
              "result": [
                { "hostid": "10461", "name": "BSD-USW102-3", "hostgroups": [ { "groupid": "9", "name": "Templates/Network devices" } ] }
              ],
              "id": 1
            }
            """.data(using: .utf8)
        )

        let response = try JSONDecoder().decode(ZabbixAPIResponse<[ZabbixHostGroupLookup]>.self, from: responseData)
        let hosts = try response.resolvedResult()

        #expect(hosts.first?.hostgroups.first?.name == "Templates/Network devices")
    }

    @Test func zabbixAPIResponseDecodesActiveTriggerSummary() throws {
        let responseData = try #require(
            """
            {
              "jsonrpc": "2.0",
              "result": [
                { "triggerid": "47242", "description": "Interface down", "priority": "3", "hosts": [ { "hostid": "10461", "name": "BSD-USW102-3" } ] }
              ],
              "id": 1
            }
            """.data(using: .utf8)
        )

        let response = try JSONDecoder().decode(ZabbixAPIResponse<[ZabbixTriggerSummary]>.self, from: responseData)
        let triggers = try response.resolvedResult()

        #expect(triggers.first?.priority.intValue == 3)
        #expect(triggers.first?.hosts.first?.hostid == "10461")
    }

    @Test func buildNavTreeOrdersByHierarchyAndDepth() throws {
        // Node 1 (root, order 1) with child 3; node 2 (root, order 0) linking a map.
        let fields = [
            ZabbixWidgetField(name: "navtree.1.name", value: "Datacenters"),
            ZabbixWidgetField(name: "navtree.1.parent", value: "0"),
            ZabbixWidgetField(name: "navtree.1.order", value: "1"),
            ZabbixWidgetField(name: "navtree.1.sysmapid", value: "0"),
            ZabbixWidgetField(name: "navtree.2.name", value: "Overview"),
            ZabbixWidgetField(name: "navtree.2.parent", value: "0"),
            ZabbixWidgetField(name: "navtree.2.order", value: "0"),
            ZabbixWidgetField(name: "navtree.2.sysmapid", value: "5"),
            ZabbixWidgetField(name: "navtree.3.name", value: "East"),
            ZabbixWidgetField(name: "navtree.3.parent", value: "1"),
            ZabbixWidgetField(name: "navtree.3.order", value: "0"),
            ZabbixWidgetField(name: "navtree.3.sysmapid", value: "7")
        ]

        let tree = DashboardManager.buildNavTree(from: fields)

        // Roots ordered by `order`: Overview (0) before Datacenters (1); East nested under it.
        #expect(tree.map(\.name) == ["Overview", "Datacenters", "East"])
        #expect(tree.map(\.depth) == [0, 0, 1])
        // sysmapid 0 → folder; non-zero → map link.
        #expect(tree.first(where: { $0.name == "Datacenters" })?.linksToMap == false)
        #expect(tree.first(where: { $0.name == "Overview" })?.linksToMap == true)
    }

    @Test func applyNavTreeSeveritiesRollsUpToParents() throws {
        // Root folder "A" (no map) with two map-linked children; folder "B" with a healthy child.
        let fields = [
            ZabbixWidgetField(name: "navtree.1.name", value: "A"), ZabbixWidgetField(name: "navtree.1.parent", value: "0"), ZabbixWidgetField(name: "navtree.1.order", value: "0"),
            ZabbixWidgetField(name: "navtree.2.name", value: "A-map1"), ZabbixWidgetField(name: "navtree.2.parent", value: "1"), ZabbixWidgetField(name: "navtree.2.order", value: "0"), ZabbixWidgetField(name: "navtree.2.sysmapid", value: "10"),
            ZabbixWidgetField(name: "navtree.3.name", value: "A-map2"), ZabbixWidgetField(name: "navtree.3.parent", value: "1"), ZabbixWidgetField(name: "navtree.3.order", value: "1"), ZabbixWidgetField(name: "navtree.3.sysmapid", value: "11"),
            ZabbixWidgetField(name: "navtree.4.name", value: "B"), ZabbixWidgetField(name: "navtree.4.parent", value: "0"), ZabbixWidgetField(name: "navtree.4.order", value: "1"),
            ZabbixWidgetField(name: "navtree.5.name", value: "B-map"), ZabbixWidgetField(name: "navtree.5.parent", value: "4"), ZabbixWidgetField(name: "navtree.5.order", value: "0"), ZabbixWidgetField(name: "navtree.5.sysmapid", value: "12")
        ]
        let tree = DashboardManager.buildNavTree(from: fields)

        // map 10 = warning(2), map 11 = disaster(5), map 12 = OK(0).
        let severities = DashboardManager.applyNavTreeSeverities(tree, severityBySysmapID: ["10": 2, "11": 5, "12": 0])
        let byName = Dictionary(uniqueKeysWithValues: severities.map { ($0.name, $0.severity) })

        #expect(byName["A-map1"] == 2)
        #expect(byName["A-map2"] == 5)
        // Folder A rolls up to its worst child (disaster 5).
        #expect(byName["A"] == 5)
        // Folder B and its healthy child stay OK.
        #expect(byName["B"] == 0)
        #expect(byName["B-map"] == 0)
    }

    @Test func buildNavTreeHandlesOrphansAndCycles() throws {
        // Node 5's parent (9) doesn't exist → emitted at top level. Nodes 1↔2 form a cycle.
        let fields = [
            ZabbixWidgetField(name: "navtree.5.name", value: "Orphan"),
            ZabbixWidgetField(name: "navtree.5.parent", value: "9"),
            ZabbixWidgetField(name: "navtree.1.name", value: "A"),
            ZabbixWidgetField(name: "navtree.1.parent", value: "2"),
            ZabbixWidgetField(name: "navtree.2.name", value: "B"),
            ZabbixWidgetField(name: "navtree.2.parent", value: "1")
        ]

        let tree = DashboardManager.buildNavTree(from: fields)
        // Every node appears exactly once despite the broken parent ref and the cycle.
        #expect(tree.count == 3)
        #expect(Set(tree.map(\.name)) == ["Orphan", "A", "B"])

        #expect(DashboardManager.buildNavTree(from: []).isEmpty)
    }

    @Test func mapElementSeverityByType() throws {
        func ref(host: String? = nil, trigger: String? = nil, group: String? = nil) -> ZabbixMapElementReference {
            ZabbixMapElementReference(hostid: host, triggerid: trigger, groupid: group, sysmapid: nil)
        }
        let byHost = ["h1": 4]
        let byTrigger = ["t1": 2, "t2": 5]
        let byGroup = ["g1": 3]

        func severity(type: Int, _ refs: [ZabbixMapElementReference]) -> Int {
            DashboardManager.mapElementSeverity(elementType: type, references: refs, severityByHostID: byHost, severityByTriggerID: byTrigger, severityByGroupID: byGroup)
        }

        // Host element → its host's severity.
        #expect(severity(type: 0, [ref(host: "h1")]) == 4)
        // Trigger element → worst of its referenced triggers.
        #expect(severity(type: 2, [ref(trigger: "t1"), ref(trigger: "t2")]) == 5)
        // Host-group element → the group's severity.
        #expect(severity(type: 3, [ref(group: "g1")]) == 3)
        // Submap (1) and image (4) elements have no computed severity → 0 (OK).
        #expect(severity(type: 1, [ref()]) == 0)
        #expect(severity(type: 4, [ref()]) == 0)
        // An element referencing something with no active problem → 0.
        #expect(severity(type: 0, [ref(host: "unknown")]) == 0)
    }

    @Test func serverRunningInferredFromHANodeStatuses() throws {
        // An active node (3) means the server is up.
        #expect(DashboardManager.isServerRunning(fromHANodeStatuses: [0, 3]) == true)
        // Nodes exist but none active → down.
        #expect(DashboardManager.isServerRunning(fromHANodeStatuses: [0, 1, 2]) == false)
        // No nodes (standalone/older server) → unknown, caller falls back to the proxy.
        #expect(DashboardManager.isServerRunning(fromHANodeStatuses: []) == nil)
    }

    @Test func haNodeStatusLabelsCoverAllStates() throws {
        #expect(DashboardManager.haNodeStatusLabel(0) == "Standby")
        #expect(DashboardManager.haNodeStatusLabel(1) == "Stopped")
        #expect(DashboardManager.haNodeStatusLabel(2) == "Unavailable")
        #expect(DashboardManager.haNodeStatusLabel(3) == "Active")
        #expect(DashboardManager.haNodeStatusLabel(99) == "Unknown")
    }

    @Test func clockTimeZoneIdentifierIgnoresLocalSentinels() throws {
        func identifier(_ value: String?) -> String? {
            DashboardManager.clockTimeZoneIdentifier(from: value.map { [ZabbixWidgetField(name: "tzone_timezone", value: $0)] } ?? [])
        }
        #expect(identifier("America/New_York") == "America/New_York")
        #expect(identifier("local") == nil)
        #expect(identifier("system") == nil)
        #expect(identifier("") == nil)
        #expect(identifier(nil) == nil)
    }

    @Test func hostTimeOffsetIsReportedMinusCollected() throws {
        // Host reported 1700000600 when the sample was collected at 1700000000 → +600s ahead.
        #expect(DashboardManager.hostTimeOffset(lastValue: "1700000600", lastClock: "1700000000") == 600)
        // Missing or non-numeric → no offset (fall back to local time).
        #expect(DashboardManager.hostTimeOffset(lastValue: nil, lastClock: "1700000000") == nil)
        #expect(DashboardManager.hostTimeOffset(lastValue: "not-a-number", lastClock: "1700000000") == nil)
    }

    @Test func problemsAcknowledgedFilterMapsStatus() throws {
        func filter(_ value: String?) -> Bool? {
            DashboardManager.problemsAcknowledgedFilter(from: value.map { [ZabbixWidgetField(name: "acknowledgement_status", value: $0)] } ?? [])
        }
        #expect(filter("1") == false)  // unacknowledged only
        #expect(filter("2") == true)   // acknowledged only
        #expect(filter("0") == nil)    // all
        #expect(filter(nil) == nil)    // field absent → no filter
    }

    @Test func severityAcknowledgedFilterOnlyRestrictsUnacknowledged() throws {
        func filter(_ value: String?) -> Bool? {
            DashboardManager.severityAcknowledgedFilter(from: value.map { [ZabbixWidgetField(name: "ext_ack", value: $0)] } ?? [])
        }
        #expect(filter("1") == false)  // unacknowledged only
        #expect(filter("0") == nil)    // all
        #expect(filter("2") == nil)    // separated display → count all
        #expect(filter(nil) == nil)    // field absent → no filter
    }

    @Test func durationSecondsParsesUnitsAndSign() throws {
        #expect(DashboardManager.durationSeconds(from: "3600") == 3600)   // plain seconds
        #expect(DashboardManager.durationSeconds(from: "30s") == 30)
        #expect(DashboardManager.durationSeconds(from: "5m") == 300)      // m = minutes
        #expect(DashboardManager.durationSeconds(from: "2h") == 7200)
        #expect(DashboardManager.durationSeconds(from: "1d") == 86400)
        #expect(DashboardManager.durationSeconds(from: "1w") == 604800)
        #expect(DashboardManager.durationSeconds(from: "-1h") == -3600)   // signed
        #expect(DashboardManager.durationSeconds(from: "") == nil)
        #expect(DashboardManager.durationSeconds(from: "abc") == nil)
    }

    @Test func aggregatedByIntervalBucketsWithFunction() throws {
        let start = Date(timeIntervalSince1970: 1_000_000)
        func at(_ offset: Double, _ value: Double) -> (date: Date, value: Double) {
            (date: start.addingTimeInterval(offset), value: value)
        }
        // Two 60s buckets: [10,20,30] then [100].
        let points = [at(0, 10), at(20, 20), at(50, 30), at(70, 100)]

        // Avg (3): bucket 0 → 20, bucket 1 → 100; placed at each bucket's midpoint (+30s, +90s).
        let avg = DashboardManager.aggregatedByInterval(points, function: 3, intervalSeconds: 60, windowStart: start)
        #expect(avg.map(\.value) == [20, 100])
        #expect(avg.first?.date == start.addingTimeInterval(30))

        // Max (2): bucket 0 → 30, bucket 1 → 100.
        #expect(DashboardManager.aggregatedByInterval(points, function: 2, intervalSeconds: 60, windowStart: start).map(\.value) == [30, 100])

        // Function 0 or non-positive interval → points unchanged.
        #expect(DashboardManager.aggregatedByInterval(points, function: 0, intervalSeconds: 60, windowStart: start).count == 4)
        #expect(DashboardManager.aggregatedByInterval(points, function: 3, intervalSeconds: 0, windowStart: start).count == 4)
    }

    @Test func trendApproximationSelectsMinAvgMax() throws {
        let full = ZabbixTrendValue(clock: "1700000000", value_avg: "50", value_min: "10", value_max: "90")

        #expect(DashboardManager.trendValue(from: full, approximation: 1) == "10") // min
        #expect(DashboardManager.trendValue(from: full, approximation: 2) == "50") // avg
        #expect(DashboardManager.trendValue(from: full, approximation: 3) == "90") // max
        #expect(DashboardManager.trendValue(from: full, approximation: 0) == "50") // "all" → avg
        #expect(DashboardManager.trendValue(from: full, approximation: 99) == "50") // unknown → avg

        // When only value_avg was requested, min/max fall back to it.
        let avgOnly = ZabbixTrendValue(clock: "1700000000", value_avg: "50", value_min: nil, value_max: nil)
        #expect(DashboardManager.trendValue(from: avgOnly, approximation: 1) == "50")
        #expect(DashboardManager.trendValue(from: avgOnly, approximation: 3) == "50")
    }

    @Test func slaPercentFormattingTrimsTrailingZeros() throws {
        // Configured SLO strings render trimmed.
        #expect(DashboardManager.formatSLOPercent("99.9000") == "99.9%")
        #expect(DashboardManager.formatSLOPercent("100.0000") == "100%")
        // Computed SLI doubles trim to at most four decimals.
        #expect(DashboardManager.formatSLIPercent(99.95420) == "99.9542%")
        #expect(DashboardManager.formatSLIPercent(99.9) == "99.9%")
        #expect(DashboardManager.formatSLIPercent(100) == "100%")
    }

    @Test func slaGetSliResponseDecodesPeriodServiceMatrix() throws {
        let responseData = try #require(
            """
            {
              "jsonrpc": "2.0",
              "result": {
                "periods": [ { "period_from": 1700000000, "period_to": 1700086400 } ],
                "serviceids": [ "12", "34" ],
                "sli": [ [ { "sli": 99.95, "uptime": 86000, "downtime": 400 }, { "sli": 98.10, "uptime": 84000, "downtime": 2400 } ] ]
              },
              "id": 1
            }
            """.data(using: .utf8)
        )

        let response = try JSONDecoder().decode(ZabbixAPIResponse<ZabbixSLI>.self, from: responseData)
        let report = try response.resolvedResult()
        #expect(report.serviceids == ["12", "34"])
        #expect(report.sli.first?.count == 2)
        #expect(report.sli.first?[0].sli == 99.95)
        #expect(report.sli.first?[1].sli == 98.10)
    }

    @Test func rankTriggersByFrequencyCountsAndOrders() throws {
        let events = [
            ZabbixEventSummary(eventid: "1", objectid: "T1", severity: ZabbixNumericString(intValue: 3), name: "T1 v1", clock: "100"),
            ZabbixEventSummary(eventid: "2", objectid: "T1", severity: ZabbixNumericString(intValue: 4), name: "T1 v2", clock: "300"),
            ZabbixEventSummary(eventid: "3", objectid: "T1", severity: ZabbixNumericString(intValue: 2), name: "T1 v3", clock: "200"),
            ZabbixEventSummary(eventid: "4", objectid: "T2", severity: ZabbixNumericString(intValue: 5), name: "T2", clock: "250")
        ]

        let ranked = DashboardManager.rankTriggersByFrequency(events)

        // T1 fired 3× → ranks above T2 (1×) despite T2's higher severity.
        #expect(ranked.map(\.triggerID) == ["T1", "T2"])
        #expect(ranked[0].count == 3)
        #expect(ranked[1].count == 1)
        // Name comes from the most recent event (clock 300), severity is the worst seen (4).
        #expect(ranked[0].name == "T1 v2")
        #expect(ranked[0].severity == 4)
        #expect(ranked[0].latest == 300)
    }

    @Test func rankTriggersBreaksCountTiesBySeverity() throws {
        let events = [
            ZabbixEventSummary(eventid: "1", objectid: "low", severity: ZabbixNumericString(intValue: 1), name: "low", clock: "100"),
            ZabbixEventSummary(eventid: "2", objectid: "high", severity: ZabbixNumericString(intValue: 5), name: "high", clock: "100")
        ]

        // Both fired once → the worse-severity trigger ranks first.
        #expect(DashboardManager.rankTriggersByFrequency(events).map(\.triggerID) == ["high", "low"])
    }

    @Test func webScenarioStatusDerivesFromFailValue() throws {
        // 0 → Ok, > 0 → Failed (the failed step), missing/non-numeric → Unknown.
        #expect(DashboardManager.webScenarioStatus(fromFailValue: "0") == .ok)
        #expect(DashboardManager.webScenarioStatus(fromFailValue: "3") == .failed)
        #expect(DashboardManager.webScenarioStatus(fromFailValue: nil) == .unknown)
        #expect(DashboardManager.webScenarioStatus(fromFailValue: "") == .unknown)
    }

    @Test func webScenarioNameParsesFromFailKey() throws {
        #expect(DashboardManager.scenarioName(fromFailKey: "web.test.fail[Homepage]") == "Homepage")
        #expect(DashboardManager.scenarioName(fromFailKey: "web.test.fail[Login flow]") == "Login flow")
        // Non-fail keys and the sibling error item are rejected.
        #expect(DashboardManager.scenarioName(fromFailKey: "web.test.error[Homepage]") == nil)
        #expect(DashboardManager.scenarioName(fromFailKey: "system.cpu.load") == nil)
    }

    @Test func webFailItemDecodesKeyUnderscoreField() throws {
        let responseData = try #require(
            """
            {
              "jsonrpc": "2.0",
              "result": [
                { "itemid": "5501", "key_": "web.test.fail[Homepage]", "lastvalue": "0", "hostid": "10461" }
              ],
              "id": 1
            }
            """.data(using: .utf8)
        )

        let response = try JSONDecoder().decode(ZabbixAPIResponse<[ZabbixWebFailItem]>.self, from: responseData)
        let items = try response.resolvedResult()
        #expect(items.first?.key_ == "web.test.fail[Homepage]")
        #expect(items.first?.lastvalue == "0")
        #expect(items.first?.hostid == "10461")
    }

    @Test func expandMacrosResolvesKnownTokensAndKeepsUnknown() throws {
        let macros = ["HOST.NAME": "web-01", "ITEM.NAME": "CPU load", "ITEM.LASTVALUE": "0.42"]

        // Base macros resolve.
        #expect(DashboardManager.expandMacros("{HOST.NAME}: {ITEM.NAME}", macros) == "web-01: CPU load")
        // Single-item numbered variant resolves to the same value.
        #expect(DashboardManager.expandMacros("{ITEM.NAME1} = {ITEM.LASTVALUE1}", macros) == "CPU load = 0.42")
        // Unknown macros are left untouched (not blanked).
        #expect(DashboardManager.expandMacros("{ITEM.NAME} @ {EVENT.NAME}", macros) == "CPU load @ {EVENT.NAME}")
        // A plain string with no macros is unchanged.
        #expect(DashboardManager.expandMacros("Static label", macros) == "Static label")
    }

    @Test func formattedItemValueFormatsNumericButPreservesMappedAndText() throws {
        let map = ZabbixValueMap(mappings: [ZabbixValueMapping(type: nil, value: "1", newvalue: "Up")])

        // Numeric, unmapped → formatted with units + precision.
        #expect(DashboardManager.formattedItemValue(rawValue: "42", units: "%", valueMap: nil, decimalPlaces: 1) == "42.0 %")
        // Value-mapped → "Label (raw)", unchanged regardless of precision.
        #expect(DashboardManager.formattedItemValue(rawValue: "1", units: "", valueMap: map, decimalPlaces: 2) == "Up (1)")
        // Non-numeric text → passed through as-is.
        #expect(DashboardManager.formattedItemValue(rawValue: "running", units: "", valueMap: nil, decimalPlaces: 2) == "running")
        // Absent → em dash.
        #expect(DashboardManager.formattedItemValue(rawValue: nil, units: "%", valueMap: nil, decimalPlaces: 2) == "\u{2014}")
    }

    @Test func itemValueFormattingHonorsDecimalPlacesAndUnits() throws {
        // Default 2 decimals with a unit suffix.
        #expect(ZabbixValueFormatting.formatItemValue(1, units: "%") == "1.00 %")
        // decimal_places = 0 → integer; = 3 → three places.
        #expect(ZabbixValueFormatting.formatItemValue(1.5, units: "%", decimalPlaces: 0) == "2 %")
        #expect(ZabbixValueFormatting.formatItemValue(0.4237, units: "", decimalPlaces: 3) == "0.424")
        // Empty units (units_show off) → no suffix.
        #expect(ZabbixValueFormatting.formatItemValue(42, units: "", decimalPlaces: 2) == "42.00")
        // Metric scaling still applies, with the chosen precision.
        #expect(ZabbixValueFormatting.formatItemValue(1_500_000, units: "bps", decimalPlaces: 1) == "1.5 Mbps")
        // Out-of-range decimals are clamped (no crash).
        #expect(ZabbixValueFormatting.formatItemValue(1, units: "", decimalPlaces: -3) == "1")
    }

    @Test func thresholdColorPicksHighestBandMet() throws {
        let fields = [
            ZabbixWidgetField(name: "thresholds.0.threshold", value: "50"),
            ZabbixWidgetField(name: "thresholds.0.color", value: "FFFF00"),
            ZabbixWidgetField(name: "thresholds.1.threshold", value: "90"),
            ZabbixWidgetField(name: "thresholds.1.color", value: "FF0000")
        ]

        // Below every threshold → no alert color (caller falls back to bg_color).
        #expect(DashboardManager.thresholdColorHex(for: 20, fields: fields) == nil)
        // Between the two bands → the lower band's color.
        #expect(DashboardManager.thresholdColorHex(for: 75, fields: fields) == "FFFF00")
        // Exactly on a threshold counts as meeting it.
        #expect(DashboardManager.thresholdColorHex(for: 90, fields: fields) == "FF0000")
        // Above the top band → the top band's color.
        #expect(DashboardManager.thresholdColorHex(for: 200, fields: fields) == "FF0000")
        // No thresholds configured, or no value → nil.
        #expect(DashboardManager.thresholdColorHex(for: 75, fields: []) == nil)
        #expect(DashboardManager.thresholdColorHex(for: nil, fields: fields) == nil)
    }

    @Test func webScenarioParamsForwardTagFilterWhenPresent() throws {
        func encoded(_ params: ZabbixWebScenarioGetParameters) throws -> [String: Any] {
            let data = try JSONEncoder().encode(params)
            return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        }

        // No tags → unfiltered (no tags/evaltype keys).
        let untagged = try encoded(ZabbixWebScenarioGetParameters(groupIDs: ["7"]))
        #expect(untagged["tags"] == nil)
        #expect(untagged["evaltype"] == nil)

        // Tag filter forwarded to httptest.get with its evaltype.
        let tagged = try encoded(ZabbixWebScenarioGetParameters(
            tags: [ZabbixTagFilter(tag: "env", value: "prod", operator: 1)],
            evaltype: 0
        ))
        #expect((tagged["tags"] as? [[String: Any]])?.count == 1)
        #expect(tagged["evaltype"] as? Int == 0)
    }

    @Test func itemSearchParamsForwardTagFilterWhenPresent() throws {
        func encoded(_ params: ZabbixItemSearchParameters) throws -> [String: Any] {
            let data = try JSONEncoder().encode(params)
            return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        }

        // No tags → the query stays unfiltered (no tags/evaltype keys sent).
        let untagged = try encoded(ZabbixItemSearchParameters(groupIDs: ["4"]))
        #expect(untagged["tags"] == nil)
        #expect(untagged["evaltype"] == nil)

        // Item-tag filter is forwarded to item.get with its evaltype.
        let tagged = try encoded(ZabbixItemSearchParameters(
            tags: [ZabbixTagFilter(tag: "Application", value: "MySQL", operator: 0)],
            evaltype: 2
        ))
        #expect((tagged["tags"] as? [[String: Any]])?.count == 1)
        #expect(tagged["evaltype"] as? Int == 2)

        // An empty tag array is treated as no filter (evaltype dropped too).
        let emptyTags = try encoded(ZabbixItemSearchParameters(tags: [], evaltype: 2))
        #expect(emptyTags["tags"] == nil)
        #expect(emptyTags["evaltype"] == nil)
    }

    @Test func alertParamsForwardContentFiltersWhenPresent() throws {
        func encoded(_ params: ZabbixAlertGetParameters) throws -> [String: Any] {
            let data = try JSONEncoder().encode(params)
            return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        }

        // No filters → only the base query (no filter/actionids/etc. keys).
        let base = try encoded(ZabbixAlertGetParameters(sinceUnixTime: 100))
        #expect(base["actionids"] == nil)
        #expect(base["userids"] == nil)
        #expect(base["mediatypeids"] == nil)
        #expect(base["filter"] == nil)

        // Configured filters are forwarded; statuses go under filter:{status:[...]}.
        let filtered = try encoded(ZabbixAlertGetParameters(
            sinceUnixTime: 100,
            actionIDs: ["4"],
            mediatypeIDs: ["1", "2"],
            userIDs: ["7"],
            statuses: [0, 2]
        ))
        #expect(filtered["actionids"] as? [String] == ["4"])
        #expect((filtered["mediatypeids"] as? [String])?.count == 2)
        #expect(filtered["userids"] as? [String] == ["7"])
        let filter = try #require(filtered["filter"] as? [String: Any])
        #expect((filter["status"] as? [Int]) == [0, 2])

        // Empty arrays are treated as no filter.
        let empties = try encoded(ZabbixAlertGetParameters(sinceUnixTime: 100, actionIDs: [], statuses: []))
        #expect(empties["actionids"] == nil)
        #expect(empties["filter"] == nil)
    }

    @Test func discoveryRuleParamsFilterToActiveRules() throws {
        func encoded(_ params: ZabbixDiscoveryRuleGetParameters) throws -> [String: Any] {
            let data = try JSONEncoder().encode(params)
            return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        }

        // Default: only enabled discovery rules, sorted by name — matching Zabbix's widget.
        let active = try encoded(ZabbixDiscoveryRuleGetParameters())
        let filter = try #require(active["filter"] as? [String: Any])
        #expect(filter["status"] as? Int == 0)
        #expect(active["sortfield"] as? [String] == ["name"])

        // Opt out to include disabled rules too.
        let all = try encoded(ZabbixDiscoveryRuleGetParameters(activeOnly: false))
        #expect(all["filter"] == nil)
    }

    @Test func triggerOverviewParamsIncludeProblemFilterOnlyWhenRequested() throws {
        func encoded(_ params: ZabbixActiveTriggerGetParameters) throws -> [String: Any] {
            let data = try JSONEncoder().encode(params)
            return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        }

        // "Problems"/"Recent problems" — restrict to PROBLEM-state triggers.
        let problemsOnly = try encoded(ZabbixActiveTriggerGetParameters(onlyProblems: true))
        let filter = try #require(problemsOnly["filter"] as? [String: Any])
        #expect(filter["value"] as? Int == 1)

        // "Any" — no state filter, so OK triggers come back too.
        let any = try encoded(ZabbixActiveTriggerGetParameters(onlyProblems: false))
        #expect(any["filter"] == nil)

        // Tag filter is forwarded with its evaltype when present.
        let tagged = try encoded(ZabbixActiveTriggerGetParameters(
            onlyProblems: false,
            tags: [ZabbixTagFilter(tag: "service", value: "web", operator: 1)],
            evaltype: 2
        ))
        #expect((tagged["tags"] as? [[String: Any]])?.count == 1)
        #expect(tagged["evaltype"] as? Int == 2)
    }

    @Test func zabbixAPIResponseDecodesGraphDefinitionGitemsKey() throws {
        // graph.get's selectGraphItems response key is "gitems" (verified against a live Zabbix
        // 7.0 server), not "graphitems".
        let responseData = try #require(
            """
            {
              "jsonrpc": "2.0",
              "result": [
                { "graphid": "392", "name": "Zabbix server performance", "gitems": [ { "itemid": "22187", "color": "00C800" } ] }
              ],
              "id": 1
            }
            """.data(using: .utf8)
        )

        let response = try JSONDecoder().decode(ZabbixAPIResponse<[ZabbixGraphDefinition]>.self, from: responseData)
        let graphs = try response.resolvedResult()

        #expect(graphs.first?.gitems.first?.itemid == "22187")
        #expect(graphs.first?.gitems.first?.color == "00C800")
        // graphtype is absent here → decodes to nil (treated as normal/line).
        #expect(graphs.first?.graphtype == nil)
    }

    @Test func graphDefinitionDecodesPieGraphType() throws {
        let responseData = try #require(
            """
            {
              "jsonrpc": "2.0",
              "result": [
                { "graphid": "7", "name": "Disk usage", "graphtype": "2", "gitems": [ { "itemid": "9", "color": "FF0000" } ] }
              ],
              "id": 1
            }
            """.data(using: .utf8)
        )

        let graphs = try JSONDecoder().decode(ZabbixAPIResponse<[ZabbixGraphDefinition]>.self, from: responseData).resolvedResult()
        // graphtype 2 = pie, so the resolver renders slices rather than lines.
        #expect(graphs.first?.graphtype?.intValue == 2)
    }

    @Test func widgetFieldHelpersGroupNestedDatasetFields() throws {
        // svggraph's dataset fields are doubly-indexed ("ds.0.hosts.0", "ds.0.items.0"), verified
        // against a live Zabbix 7.0 server. indexedFieldGroups must preserve the ".0" suffix on the
        // sub-key rather than splitting on every dot.
        let fields = [
            ZabbixWidgetField(name: "ds.0.hosts.0", value: "Kismet-Data Center"),
            ZabbixWidgetField(name: "ds.0.items.0", value: "Temperature"),
            ZabbixWidgetField(name: "ds.0.color", value: "FF465C")
        ]

        let datasets = DashboardManager.indexedFieldGroups(fields, prefix: "ds")

        #expect(datasets.count == 1)
        #expect(datasets[0]["hosts.0"] == "Kismet-Data Center")
        #expect(datasets[0]["items.0"] == "Temperature")
        #expect(datasets[0]["color"] == "FF465C")
    }

    @Test func hostInventoryDecodesBothEmptyArrayAndPopulatedObjectShapes() throws {
        // host.get's "inventory" field is an empty array [] when inventory isn't populated for a
        // host, but a keyed object when it is — verified against a live Zabbix 7.0 server.
        let emptyArrayData = try #require(
            """
            { "hostid": "10084", "name": "Zabbix Server", "inventory": [] }
            """.data(using: .utf8)
        )
        let populatedData = try #require(
            """
            { "hostid": "11426", "name": "Kismet-Data Center", "inventory": { "location_lat": "40.6892", "location_lon": "-74.0466" } }
            """.data(using: .utf8)
        )

        let emptyHost = try JSONDecoder().decode(ZabbixHostWithInventory.self, from: emptyArrayData)
        let populatedHost = try JSONDecoder().decode(ZabbixHostWithInventory.self, from: populatedData)

        #expect(emptyHost.inventory.locationLatitude == nil)
        #expect(populatedHost.inventory.locationLatitude == "40.6892")
        #expect(populatedHost.inventory.locationLongitude == "-74.0466")
    }

    @Test func zabbixAPIResponseDecodesNetworkMapTopology() throws {
        let responseData = try #require(
            """
            {
              "jsonrpc": "2.0",
              "result": [
                {
                  "sysmapid": "3",
                  "name": "District High Level Topology",
                  "width": "1800",
                  "height": "850",
                  "backgroundid": "191",
                  "selements": [
                    { "selementid": "6", "elementtype": "0", "label": "{HOST.NAME}", "x": "100", "y": "50", "iconid_off": "155", "elements": [ { "hostid": "10084" } ] },
                    { "selementid": "5", "elementtype": "4", "label": "Core Switch", "x": "300", "y": "50", "iconid_off": "1", "elements": [] }
                  ],
                  "links": [
                    {
                      "linkid": "3",
                      "selementid1": "6",
                      "selementid2": "5",
                      "color": "00CC00",
                      "linktriggers": [ { "triggerid": "18670", "color": "DD0000" } ]
                    }
                  ]
                }
              ],
              "id": 1
            }
            """.data(using: .utf8)
        )

        let response = try JSONDecoder().decode(ZabbixAPIResponse<[ZabbixNetworkMap]>.self, from: responseData)
        let map = try #require(response.resolvedResult().first)

        #expect(map.selements.count == 2)
        #expect(map.selements[0].elements.first?.hostid == "10084")
        #expect(map.links.first?.linktriggers.first?.color == "DD0000")
        #expect(map.backgroundid == "191")
    }

    @Test func zabbixAPIResponseDecodesImageBase64Content() throws {
        let responseData = try #require(
            """
            {
              "jsonrpc": "2.0",
              "result": [
                { "imageid": "191", "image": "aGVsbG8=" }
              ],
              "id": 1
            }
            """.data(using: .utf8)
        )

        let response = try JSONDecoder().decode(ZabbixAPIResponse<[ZabbixImage]>.self, from: responseData)
        let image = try #require(response.resolvedResult().first)
        let decodedData = try #require(Data(base64Encoded: image.image))

        #expect(String(data: decodedData, encoding: .utf8) == "hello")
    }

    @Test func refreshIntervalSecondsParsesRfRateField() throws {
        // "rf_rate" verified on a live server's "problems" (30s) and "systeminfo" (120s) widgets.
        let thirtySeconds = [ZabbixWidgetField(name: "rf_rate", value: "30")]
        // "0" is Zabbix's "No refresh". On an unattended display that can't be manually refreshed,
        // it falls back to the slowest interval rather than freezing forever.
        let noRefresh = [ZabbixWidgetField(name: "rf_rate", value: "0")]
        // A widget left at "Default" stores no rf_rate field; Zabbix refreshes it at 60s, so it
        // must keep updating rather than freezing on its launch-time snapshot.
        let absent: [ZabbixWidgetField] = []

        #expect(DashboardManager.refreshIntervalSeconds(from: thirtySeconds) == 30)
        #expect(DashboardManager.refreshIntervalSeconds(from: noRefresh) == DashboardManager.maximumRefreshIntervalSeconds)
        #expect(DashboardManager.refreshIntervalSeconds(from: absent) == DashboardManager.defaultRefreshIntervalSeconds)
    }

    @Test func timePeriodHonorsFromToAndDefaults() throws {
        // Fixed reference time so the relative-time resolution is deterministic. Spans use a loose
        // tolerance so a DST boundary in the local calendar can't make an offset flake by an hour.
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        // Explicit "last 6 hours".
        let sixHours = [ZabbixWidgetField(name: "time_period.from", value: "now-6h"), ZabbixWidgetField(name: "time_period.to", value: "now")]
        let p6 = DashboardManager.timePeriod(from: sixHours, now: now)
        #expect(p6.end == now)
        #expect(p6.end.timeIntervalSince(p6.start) > 5 * 3600 && p6.end.timeIntervalSince(p6.start) < 7 * 3600)

        // No time_period fields -> Zabbix's global "last 1 hour" default.
        let def = DashboardManager.timePeriod(from: [], now: now)
        #expect(def.end == now)
        #expect(def.end.timeIntervalSince(def.start) > 0.9 * 3600 && def.end.timeIntervalSince(def.start) < 1.1 * 3600)

        // A window that ends in the PAST is now honored (previously .to was dropped and end was
        // always "now").
        let pastWindow = [ZabbixWidgetField(name: "time_period.from", value: "now-2d"), ZabbixWidgetField(name: "time_period.to", value: "now-1d")]
        let pw = DashboardManager.timePeriod(from: pastWindow, now: now)
        #expect(pw.end < now)
        #expect(pw.start < pw.end)

        // A calendar-aligned expression ("today") that the old parser rejected now yields a valid,
        // ordered range within the last day.
        let today = [ZabbixWidgetField(name: "time_period.from", value: "now/d"), ZabbixWidgetField(name: "time_period.to", value: "now")]
        let td = DashboardManager.timePeriod(from: today, now: now)
        #expect(td.start < td.end)
        #expect(now.timeIntervalSince(td.start) <= 24 * 3600)
    }

    @Test func bucketedChartPointsPreservesPeaksAndMarksGaps() throws {
        let start = Date(timeIntervalSince1970: 0)
        let end = Date(timeIntervalSince1970: 12000)

        // A cluster of closely-spaced samples (300s apart, well under the outage threshold), with a
        // sharp spike, then a long stretch of no data, then one more sample. The cluster must stay a
        // continuous line; only the long empty stretch is a real gap.
        let points: [(date: Date, value: Double)] = [
            (Date(timeIntervalSince1970: 300), 5),
            (Date(timeIntervalSince1970: 600), 100),   // spike
            (Date(timeIntervalSince1970: 900), 6),
            (Date(timeIntervalSince1970: 11000), 7)    // after a ~2.8h outage
        ]

        let result = DashboardManager.bucketedChartPoints(points, itemID: "1", windowStart: start, windowEnd: end, bucketCount: 10)

        // The spike survives.
        #expect(result.compactMap(\.value).contains(100))

        // The 300s-spaced cluster is NOT broken — only the long outage inserts exactly one gap,
        // sitting between the cluster and the trailing sample.
        let gaps = result.filter { $0.value == nil }
        #expect(gaps.count == 1)
        if let gap = gaps.first {
            #expect(gap.date > Date(timeIntervalSince1970: 900))
            #expect(gap.date < Date(timeIntervalSince1970: 11000))
        }

        // The trailing sample stays at its real time near the end of the window.
        #expect(result.contains { $0.value == 7 && $0.date == Date(timeIntervalSince1970: 11000) })
    }

    @Test func valueMapResolvesRawReadingsToLabels() throws {
        // A typical status value map (0 -> Down, 1 -> Up) with a default fallback.
        let json = Data("""
        {"mappings":[
          {"type":"0","value":"0","newvalue":"Down"},
          {"type":"0","value":"1","newvalue":"Up"},
          {"type":"5","value":"","newvalue":"Unknown"}
        ]}
        """.utf8)
        let map = try JSONDecoder().decode(ZabbixValueMap.self, from: json)

        #expect(map.mappedText(for: "1") == "Up")
        #expect(map.mappedText(for: "0") == "Down")
        // A float reading of the same value still matches the integer mapping.
        #expect(map.mappedText(for: "1.00") == "Up")
        // Anything unmapped falls back to the default rule.
        #expect(map.mappedText(for: "7") == "Unknown")
    }

    @Test func itemValueMapDecodesEmptyArrayAsNoMap() throws {
        // Zabbix returns "valuemap": [] (an empty array, not an object) for an item without a value
        // map — this must decode to "no map" rather than failing the whole item.get response.
        let withoutMap = try JSONDecoder().decode(ZabbixItemSummary.self, from: Data("""
        {"itemid":"1","name":"CPU load","lastvalue":"0.42","valuemap":[]}
        """.utf8))
        #expect(withoutMap.valuemap?.valueMap == nil)

        let withMap = try JSONDecoder().decode(ZabbixItemSummary.self, from: Data("""
        {"itemid":"2","name":"ICMP ping","lastvalue":"1","valuemap":{"mappings":[{"type":"0","value":"1","newvalue":"Up"}]}}
        """.utf8))
        #expect(withMap.valuemap?.valueMap?.mappedText(for: "1") == "Up")
    }

    @Test func tagFiltersReadWidgetTagConfiguration() throws {
        let fields = [
            ZabbixWidgetField(name: "evaltype", value: "2"),
            ZabbixWidgetField(name: "tags.0.tag", value: "env"),
            ZabbixWidgetField(name: "tags.0.operator", value: "1"),   // Equals
            ZabbixWidgetField(name: "tags.0.value", value: "prod"),
            ZabbixWidgetField(name: "tags.1.tag", value: "team"),     // no operator -> 0 (Contains), no value -> ""
            ZabbixWidgetField(name: "tags.2.value", value: "orphan"), // no tag name -> dropped
        ]

        let filters = DashboardManager.tagFilters(from: fields)
        #expect(filters.count == 2)
        #expect(filters[0].tag == "env")
        #expect(filters[0].value == "prod")
        #expect(filters[0].operator == 1)
        #expect(filters[1].tag == "team")
        #expect(filters[1].value == "")
        #expect(filters[1].operator == 0)
        #expect(DashboardManager.tagEvalType(from: fields) == 2)

        // A widget with no tag filter yields nothing, leaving queries unfiltered.
        #expect(DashboardManager.tagFilters(from: []).isEmpty)
        #expect(DashboardManager.tagEvalType(from: []) == nil)
    }

    @Test func mappedItemValueAppliesValueMap() throws {
        let map = try JSONDecoder().decode(ZabbixValueMap.self, from: Data("""
        {"mappings":[{"type":"0","value":"1","newvalue":"Up"}]}
        """.utf8))

        // A mapped reading shows "label (raw)"; an unmapped reading, or no map at all, shows raw.
        #expect(DashboardManager.mappedItemValue(rawValue: "1", valueMap: map) == "Up (1)")
        #expect(DashboardManager.mappedItemValue(rawValue: "5", valueMap: map) == "5")
        #expect(DashboardManager.mappedItemValue(rawValue: "42", valueMap: nil) == "42")
        #expect(DashboardManager.mappedItemValue(rawValue: nil, valueMap: map) == "\u{2014}")
    }

    @Test func aggregateComputesEachFunction() throws {
        let points: [(clock: Double, value: Double)] = [(100, 10), (300, 20), (200, 30)]

        #expect(DashboardManager.aggregate(points, function: 1) == 10)   // min
        #expect(DashboardManager.aggregate(points, function: 2) == 30)   // max
        #expect(DashboardManager.aggregate(points, function: 3) == 20)   // avg (60/3)
        #expect(DashboardManager.aggregate(points, function: 4) == 3)    // count
        #expect(DashboardManager.aggregate(points, function: 5) == 60)   // sum
        #expect(DashboardManager.aggregate(points, function: 6) == 10)   // first (earliest clock 100)
        #expect(DashboardManager.aggregate(points, function: 7) == 20)   // last (latest clock 300)

        // No data, and the "none"/unknown function, both yield nil (caller shows the raw value).
        #expect(DashboardManager.aggregate([], function: 3) == nil)
        #expect(DashboardManager.aggregate(points, function: 0) == nil)
    }

}
