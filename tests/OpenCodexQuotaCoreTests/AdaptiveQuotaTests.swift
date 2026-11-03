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

private actor LinkTestHTTP: QuotaHTTPServing {
    var paths: [String] = []
    var statusReads = 0
    let changeAfterRead: Bool
    var anthropicAccountID = "a1"
    var providerReports = #"{"reports":[{"provider":"anthropic","source":"anthropic:oauth-usage","quota":{"fiveHourPercent":12,"weeklyPercent":25}}]}"#
    init(changeAfterRead: Bool = false) { self.changeAfterRead = changeAfterRead }
    func serve(anthropicAccountID: String, providerReports: String) {
        self.anthropicAccountID = anthropicAccountID
        self.providerReports = providerReports
    }
    func get(_ url: URL, headers: [String: String]) async throws -> Data {
        paths.append(url.path)
        XCTAssertEqual(url.host, "127.0.0.1")
        XCTAssertFalse(headers.values.contains("hub-token"))
        XCTAssertFalse(headers.values.contains("local-secret"))
        switch url.path {
        case "/healthz": return Data(#"{"service":"opencodex","role":"client"}"#.utf8)
        case "/opencodex-session":
            return Data(#"<meta name="opencodex-session-token" content="gui"><meta name="opencodex-session-origin" content="http://127.0.0.1:10100"><meta name="opencodex-session-server-origin" content="http://127.0.0.1:10100">"#.utf8)
        case "/api/machine/status":
            statusReads += 1
            let id = changeAfterRead && statusReads > 1 ? "changed" : "link-1"
            return Data("{\"mode\":\"client\",\"connected\":true,\"managementTransport\":\"relay\",\"sharedServerOrigin\":\"http://127.0.0.1:10100\",\"apiKeyId\":\"client-1\",\"connectedAt\":\"date\",\"link\":{\"linkId\":\"\(id)\",\"readOnly\":true}}".utf8)
        case "/api/machine/hub-relay/api/codex-auth/accounts":
            XCTAssertNil(url.query)
            XCTAssertEqual(headers["x-opencodex-api-key"], "gui")
            return Data(#"{"accounts":[{"id":"c1","plan":"pro","quota":{"weeklyPercent":20}}]}"#.utf8)
        case "/api/machine/hub-relay/api/codex-auth/active":
            return Data(#"{"autoSwitchThreshold":70}"#.utf8)
        case "/api/machine/hub-relay/api/oauth/accounts":
            XCTAssertEqual(url.query, "provider=anthropic")
            return Data("{\"activeAccountId\":\"\(anthropicAccountID)\",\"accounts\":[{\"id\":\"\(anthropicAccountID)\",\"email\":\"test@example.com\"}]}".utf8)
        case "/api/machine/hub-relay/api/provider-quotas":
            XCTAssertNil(url.query)
            return Data(providerReports.utf8)
        default: XCTFail("Unexpected endpoint \(url)"); throw URLError(.badURL)
        }
    }
}

extension AdaptiveQuotaTests {
    private func linkConnection() throws -> QuotaConnection {
        try QuotaConnection.resolve(hostURL: URL(string: "http://127.0.0.1:10100")!, runningRole: "client",
            configData: Data(#"{"runtimeRole":"client","client":{"transport":"link","link":{"linkId":"link-1"},"serverUrl":"http://127.0.0.1:9999","apiKeyId":"client-1","connectedAt":"date","tokenFingerprint":"505a8c497606f899f72232a403399922417b7ca910dd96f341a44d1658a22a8f"}}"#.utf8), adminToken: "local-secret", dataToken: "hub-token")
    }
    func testLinkLoadsPassiveQuotaThroughLocalSession() async throws {
        let snapshot = await AdaptiveQuotaSnapshotLoader(connection: try linkConnection(), timeout: 5, http: LinkTestHTTP(),
            linkClaudeMemory: LinkClaudeQuotaMemory()).load().snapshot
        XCTAssertNil(snapshot.codexErrorMessage)
        XCTAssertEqual(snapshot.codexSummary?.rows.count, 1)
        XCTAssertEqual(snapshot.claudeSummary?.rows.count, 1)
        XCTAssertEqual(snapshot.claudeSummary?.weeklyRemainingPercentage, 75)
        XCTAssertTrue(snapshot.sourceLabel?.hasPrefix("Link:") == true)
    }
    func testLinkKeepsLastClaudeQuotaWhenHomeStopsHoldingReport() async throws {
        let http = LinkTestHTTP()
        let loader = AdaptiveQuotaSnapshotLoader(connection: try linkConnection(), timeout: 5, http: http,
            linkClaudeMemory: LinkClaudeQuotaMemory())
        let future = (Date().timeIntervalSince1970 + 3_600) * 1_000
        await http.serve(anthropicAccountID: "a1", providerReports: "{\"reports\":[{\"provider\":\"anthropic\",\"source\":\"anthropic:oauth-usage\",\"quota\":{\"fiveHourPercent\":15,\"fiveHourResetAt\":\(future),\"weeklyPercent\":3,\"weeklyResetAt\":\(future)}}]}")
        _ = await loader.load()

        await http.serve(anthropicAccountID: "a1", providerReports: #"{"reports":[]}"#)
        let held = await loader.load().snapshot.claudeSummary
        XCTAssertEqual(held?.fiveHourRemainingPercentage, 85)
        XCTAssertEqual(held?.weeklyRemainingPercentage, 97)

        await http.serve(anthropicAccountID: "a2", providerReports: #"{"reports":[]}"#)
        let other = await loader.load().snapshot.claudeSummary
        XCTAssertEqual(other?.rows.count, 1)
        XCTAssertNil(other?.fiveHourRemainingPercentage)
        XCTAssertNil(other?.weeklyRemainingPercentage)
    }
    func testHeldLinkClaudeQuotaTreatsPassedResetAsUnused() {
        let memory = LinkClaudeQuotaMemory()
        let now = Date()
        memory.store(LinkClaudeQuota(fiveHourPercent: 40, fiveHourResetAt: now.addingTimeInterval(-1),
            weeklyPercent: 30, weeklyResetAt: now.addingTimeInterval(60)), for: "home|a1")
        let held = memory.quota(for: "home|a1", now: now)
        XCTAssertEqual(held?.fiveHourPercent, 0)
        XCTAssertNil(held?.fiveHourResetAt)
        XCTAssertEqual(held?.weeklyPercent, 30)
        XCTAssertNil(memory.quota(for: "home|a2", now: now))
    }
    func testLinkChangeDuringReadDiscardsSnapshot() async throws {
        let snapshot = await AdaptiveQuotaSnapshotLoader(connection: try linkConnection(), timeout: 5, http: LinkTestHTTP(changeAfterRead: true)).load().snapshot
        XCTAssertFalse(snapshot.hasProviderData)
        XCTAssertEqual(snapshot.discardCachedData, true)
    }
}
