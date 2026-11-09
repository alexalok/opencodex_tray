import Foundation
import XCTest
@testable import OpenCodexQuotaCore

private let trayBody = #"{"schema":"ocx.quota-tray/1","generatedAt":1800000000000,"providers":[{"provider":"openai","weekly":{"remainingPercent":14,"resetsAt":1800000600000,"nextRecoveryAt":1800000600000,"nextRecoveryPercent":5},"resetCredits":2,"accounts":[{"name":"Work Pro","plan":"prolite","units":10,"state":"exhausted","weekly":{"remainingPercent":0,"exhausted":true},"resetCredits":{"count":2,"soonestExpiresAt":1800100000000}}]}]}"#

private actor LinkHTTP: QuotaHTTPServing {
    var paths: [String] = []
    var failNextTray = false
    func failTrayOnce() { failNextTray = true }
    func get(_ url: URL, headers: [String: String]) async throws -> Data {
        paths.append(url.path)
        XCTAssertFalse(headers.values.contains("hub-token"))
        switch url.path {
        case "/healthz": return Data(#"{"service":"opencodex","role":"client"}"#.utf8)
        case "/opencodex-session":
            return Data(#"<meta name="opencodex-session-token" content="gui"><meta name="opencodex-session-origin" content="http://127.0.0.1:10100"><meta name="opencodex-session-server-origin" content="http://127.0.0.1:10100">"#.utf8)
        case "/api/machine/status":
            return Data(#"{"mode":"client","connected":true,"managementTransport":"relay","sharedServerOrigin":"http://127.0.0.1:10100","apiKeyId":"client-1","connectedAt":"date","link":{"linkId":"link-1","readOnly":true}}"#.utf8)
        case "/api/machine/hub-relay/api/quota-pool/tray":
            XCTAssertNil(url.query)
            XCTAssertEqual(headers["x-opencodex-api-key"], "gui")
            if failNextTray { failNextTray = false; throw ConfigurationError.invalid("Quota credential rejected; reconnect OpenCodex") }
            return Data(trayBody.utf8)
        default: XCTFail("Unexpected endpoint \(url)"); throw URLError(.badURL)
        }
    }
}

private actor HubHTTP: QuotaHTTPServing {
    var paths: [String] = []
    func get(_ url: URL, headers: [String: String]) async throws -> Data {
        paths.append(url.path)
        guard url.path == "/healthz" else { XCTFail("Unexpected endpoint \(url)"); throw URLError(.badURL) }
        return Data(#"{"service":"opencodex","role":"client"}"#.utf8)
    }
}

final class TrayQuotaLoaderTests: XCTestCase {
    private let host = URL(string: "http://127.0.0.1:10100")!
    private static let hostURL = URL(string: "http://127.0.0.1:10100")!
    private static func linkConnection(_ role: String) throws -> QuotaConnection {
        try QuotaConnection.resolve(hostURL: hostURL, runningRole: role,
            configData: Data(#"{"runtimeRole":"client","client":{"transport":"link","link":{"linkId":"link-1"},"serverUrl":"http://127.0.0.1:9999","apiKeyId":"client-1","connectedAt":"date","tokenFingerprint":"505a8c497606f899f72232a403399922417b7ca910dd96f341a44d1658a22a8f"}}"#.utf8),
            adminToken: "local-secret", dataToken: "hub-token")
    }

    func testDecodesTrayQuota() throws {
        let quota = try TrayQuota.decode(Data(trayBody.utf8))
        XCTAssertEqual(quota.providers.first?.accounts.first?.units, 10)
        XCTAssertEqual(quota.providers.first?.weekly?.nextRecoveryPercent, 5)
        XCTAssertThrowsError(try TrayQuota.decode(Data(#"{"schema":"ocx.quota-pool/1","generatedAt":0,"providers":[]}"#.utf8)))
    }

    func testSteadyStateIsOneReadPerRefresh() async throws {
        let http = LinkHTTP()
        let loader = TrayQuotaLoader(baseURL: host, http: http) { role in try Self.linkConnection(role) }
        let first = await loader.load()
        XCTAssertNotNil(first.quota)
        XCTAssertEqual(first.sourceLabel, "Link: Home (link-1)")
        let checked = await http.paths.count
        let second = await loader.load()
        XCTAssertNotNil(second.quota)
        let paths = await http.paths
        XCTAssertEqual(Array(paths.dropFirst(checked)), ["/api/machine/hub-relay/api/quota-pool/tray"])
    }

    func testRejectedReadRechecksEnrollmentOnce() async throws {
        let http = LinkHTTP()
        let loader = TrayQuotaLoader(baseURL: host, http: http) { role in try Self.linkConnection(role) }
        _ = await loader.load()
        let before = await http.paths.count
        await http.failTrayOnce()
        let load = await loader.load()
        XCTAssertNotNil(load.quota)
        let after = await http.paths.dropFirst(before)
        XCTAssertEqual(after.first, "/api/machine/hub-relay/api/quota-pool/tray")
        XCTAssertTrue(after.contains("/api/machine/status"))
    }

    func testDirectHubClientFailsWithoutReading() async throws {
        let http = HubHTTP()
        let loader = TrayQuotaLoader(baseURL: host, http: http) { role in
            try QuotaConnection.resolve(hostURL: Self.hostURL, runningRole: role,
                configData: Data(#"{"runtimeRole":"client","client":{"transport":"hub","managementTransport":"direct","serverUrl":"https://hub.example.test","apiKeyId":"client-1","connectedAt":"date","tokenFingerprint":"505a8c497606f899f72232a403399922417b7ca910dd96f341a44d1658a22a8f"}}"#.utf8),
                adminToken: "local-secret", dataToken: "hub-token")
        }
        let load = await loader.load()
        XCTAssertNil(load.quota)
        XCTAssertEqual(load.sourceLabel, "Hub: hub.example.test")
        XCTAssertEqual(load.errorMessage, "Direct Hub clients are not supported; connect this machine with Link")
        let paths = await http.paths
        XCTAssertEqual(paths, ["/healthz"])
    }
}
