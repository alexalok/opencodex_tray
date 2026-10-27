import Foundation
import XCTest
@testable import OpenCodexQuotaCore

private actor TestHTTP: QuotaHTTPServing {
    var paths: [String] = []
    let changed: Bool
    init(changed: Bool = false) { self.changed = changed }
    func get(_ url: URL, headers: [String: String]) async throws -> Data {
        paths.append(url.path)
        switch url.path {
        case "/healthz": return Data(#"{"service":"opencodex","role":"client"}"#.utf8)
        case "/opencodex-session":
            XCTAssertTrue(headers.isEmpty)
            return Data(#"<meta name="opencodex-session-token" content="gui"><meta name="opencodex-session-origin" content="http://127.0.0.1:10100"><meta name="opencodex-session-server-origin" content="http://127.0.0.1:10100">"#.utf8)
        case "/api/machine/status":
            XCTAssertEqual(headers["x-opencodex-api-key"], "gui")
            return Data("{\"mode\":\"client\",\"connected\":true,\"managementTransport\":\"direct\",\"sharedServerOrigin\":\"https://hub.example\",\"apiKeyId\":\"\(changed ? "rotated" : "client-1")\",\"connectedAt\":\"2026-10-26T18:38:02.191Z\"}".utf8)
        case "/v1/hub-quota":
            XCTAssertEqual(headers["x-opencodex-api-key"], "hub-token")
            XCTAssertNil(headers["Authorization"])
            return Data(#"{"schemaVersion":1,"generatedAt":"2026-10-27T12:00:00Z","providers":{"openai":{"enabled":false,"accounts":[]},"anthropic":{"enabled":false,"accounts":[]}}}"#.utf8)
        default: XCTFail("Unexpected endpoint \(url.path)"); throw URLError(.badURL)
        }
    }
}

final class AdaptiveQuotaTests: XCTestCase {
    private func connection() throws -> QuotaConnection {
        try QuotaConnection.resolve(hostURL: URL(string: "http://127.0.0.1:10100")!, runningRole: "client",
            configData: Data(#"{"runtimeRole":"client","client":{"serverUrl":"https://hub.example","apiKeyId":"client-1","connectedAt":"2026-10-26T18:38:02.191Z","tokenFingerprint":"505a8c497606f899f72232a403399922417b7ca910dd96f341a44d1658a22a8f"}}"#.utf8), adminToken: "local-secret", dataToken: "hub-token")
    }
    func testWidgetValidatesEnrollmentBeforeSendingHubKey() async throws {
        let http = TestHTTP()
        let value = try connection()
        let loader = AdaptiveQuotaSnapshotLoader(connection: value, timeout: 5, http: http)
        let snapshot = await loader.load().snapshot
        XCTAssertEqual(snapshot.sourceID, value.sourceID)
        XCTAssertEqual(snapshot.codexEnabled, false)
        let paths = await http.paths
        XCTAssertTrue(paths.contains("/v1/hub-quota"))
    }
    func testChangedHostEnrollmentNeverSendsStaleHubKey() async throws {
        let http = TestHTTP(changed: true)
        let snapshot = await AdaptiveQuotaSnapshotLoader(connection: try connection(), timeout: 5, http: http).load().snapshot
        XCTAssertFalse(snapshot.hasProviderData)
        XCTAssertEqual(snapshot.discardCachedData, true)
        let paths = await http.paths
        XCTAssertFalse(paths.contains("/v1/hub-quota"))
    }
}
