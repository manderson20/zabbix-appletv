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
                kind: .clock(.analog)
            ),
            RenderableDashboardWidget(
                id: "2",
                title: "CPU Load",
                frame: DashboardWidgetFrame(x: 4, y: 0, width: 8, height: 4),
                refreshIntervalSeconds: 30,
                hasHiddenHeader: false,
                kind: .itemValue(name: "CPU Load", value: "0.42", units: "", backgroundColorHex: nil, trend: nil, lastUpdated: nil, mappedText: nil)
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
