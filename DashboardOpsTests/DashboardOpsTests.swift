//
//  DashboardOpsTests.swift
//  DashboardOpsTests
//
//  Created by Mathew Anderson on 7/7/26.
//

import Testing
import Foundation
@testable import DashboardOps

struct DashboardOpsTests {

    @Test @MainActor func providerRegistryMarksOnlyZabbixSupported() async throws {
        let providers = ProviderRegistry.standard.providers

        #expect(providers.count == 6)
        #expect(providers.contains { $0.kind == .zabbix && $0.supportStatus == .supported })
        #expect(providers.filter { $0.supportStatus == .supported }.count == 1)
    }

    @Test func settingsServicePersistsServerConfiguration() async throws {
        let suiteName = "DashboardOpsTests.\(UUID().uuidString)"
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
                kind: .clock
            ),
            RenderableDashboardWidget(
                id: "2",
                title: "CPU Load",
                frame: DashboardWidgetFrame(x: 4, y: 0, width: 8, height: 4),
                kind: .itemValue(name: "CPU Load", value: "0.42", units: "")
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

}
