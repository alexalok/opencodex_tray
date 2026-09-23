import Foundation
import XCTest
@testable import OpenCodexQuotaCore

private final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    private static let requestLock = NSLock()
    nonisolated(unsafe) private static var observedRequests: [String] = []

    static func reset() {
        requestLock.lock()
        observedRequests = []
        requestLock.unlock()
    }

    static func requests() -> [String] {
        requestLock.lock()
        defer { requestLock.unlock() }
        return observedRequests
    }

    private static func record(_ request: URLRequest) {
        let method = request.httpMethod ?? ""
        let path = request.url?.path ?? ""
        let query = request.url?.query.map { "?\($0)" } ?? ""
        requestLock.lock()
        observedRequests.append("\(method) \(path)\(query)")
        requestLock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            Self.record(request)
            let (response, data) = try Self.handler!(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
    override func stopLoading() {}
}

final class OpenCodexClientTests: XCTestCase {
    override func tearDown() {
        StubURLProtocol.handler = nil
        StubURLProtocol.reset()
        super.tearDown()
    }

    func testQuotaRefreshUsesOnlyReadRequestsForHighUsageAccount() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: configuration)
        StubURLProtocol.handler = { request in
            let data: Data
            switch request.url?.path {
            case "/api/codex-auth/accounts":
                data = Data(#"{"accounts":[{"id":"friend-id","alias":"workmate","plan":"prolite","isMain":false,"quota":{"weeklyPercent":70}}]}"#.utf8)
            case "/api/codex-auth/active":
                data = Data(#"{"autoSwitchThreshold":0}"#.utf8)
            case "/api/oauth/accounts":
                data = Data(#"{"accounts":[]}"#.utf8)
            default:
                XCTFail("Unexpected OpenCodex request: \(request.url?.absoluteString ?? "nil")")
                data = Data()
            }
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, data)
        }
        let client = OpenCodexClient(
            baseURL: URL(string: "https://opencodex.example")!,
            adminToken: "admin-secret",
            timeout: 5,
            session: session
        )

        let result = await QuotaSnapshotLoader(client: client).load()

        XCTAssertEqual(StubURLProtocol.requests().sorted(), [
            "GET /api/codex-auth/accounts?refresh=1",
            "GET /api/codex-auth/active",
            "GET /api/oauth/accounts?provider=anthropic&quota=1&refresh=1",
        ])
        XCTAssertEqual(result.snapshot.codexSummary?.rows, [
            AccountAllowance(
                accountId: "friend-id",
                label: "workmate",
                remainingPercent: 7.5,
                totalPercent: 25
            ),
        ])
    }

    func testAccountThresholdPrecedenceAndPublicFallback() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let client = OpenCodexClient(baseURL: URL(string: "https://opencodex.example")!,
                                     adminToken: "admin-secret", timeout: 5, session: session)
        for (status, globalBody, inheritedTotal) in [
            (200, #"{"autoSwitchThreshold":80}"#, 20.0),
            (200, #"{"autoSwitchThreshold":0}"#, 25.0),
            (200, #"{"autoSwitchThreshold":"bad"}"#, 25.0),
            (200, #"{"autoSwitchThreshold":101}"#, 25.0),
            (200, "{}", 25.0),
            (200, "not json", 25.0),
            (404, "", 25.0),
            (500, "", 25.0),
            (-1, "", 25.0),
        ] {
            StubURLProtocol.handler = { request in
                XCTAssertEqual(request.httpMethod, "GET")
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer admin-secret")
                let isGlobal = request.url?.path == "/api/codex-auth/active"
                if isGlobal && status == -1 { throw URLError(.timedOut) }
                let body = isGlobal ? globalBody : #"{"accounts":[{"id":"override","plan":"prolite","autoSwitchThresholdOverride":50,"quota":{"weeklyPercent":20}},{"id":"public","plan":"prolite","quota":{"weeklyPercent":20}},{"id":"inherit","plan":"prolite","autoSwitchThresholdOverride":null,"quota":{"weeklyPercent":20}},{"id":"invalid","plan":"prolite","autoSwitchThresholdOverride":"bad","quota":{"weeklyPercent":20}},{"id":"disabled","plan":"prolite","autoSwitchThresholdOverride":0,"quota":{"weeklyPercent":20}}]}"#
                return (HTTPURLResponse(url: request.url!, statusCode: isGlobal ? status : 200,
                                        httpVersion: nil, headerFields: nil)!, Data(body.utf8))
            }
            let accounts = try await client.fetchAccounts()
            let summary = QuotaCalculator.summarize(accounts: accounts)
            XCTAssertEqual(summary.rows.map(\.totalPercent), [12.5, inheritedTotal, inheritedTotal, inheritedTotal, 25])
            XCTAssertEqual(summary.rows.map(\.remainingPercent), [7.5, inheritedTotal - 5, inheritedTotal - 5, inheritedTotal - 5, 20])
            XCTAssertEqual(summary.trayPercentage, Int(floor(27.5 + 3 * (inheritedTotal - 5))))
        }
    }

    func testFetchClaudeAccountsUsesAnthropicPerAccountQuotaEndpoint() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: configuration)
        StubURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/oauth/accounts")
            XCTAssertEqual(request.url?.query, "provider=anthropic&quota=1&refresh=1")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer admin-secret")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let data = Data(#"{"activeAccountId":"claude-a","accounts":[{"id":"claude-a","alias":"work","email":"w***@example.com","active":true,"quota":{"weeklyPercent":35,"updatedAt":1786381200000}}]}"#.utf8)
            return (response, data)
        }
        let client = OpenCodexClient(
            baseURL: URL(string: "https://opencodex.example")!,
            adminToken: "admin-secret",
            timeout: 5,
            session: session
        )

        let accounts = try await client.fetchClaudeAccounts()

        XCTAssertEqual(accounts, [
            ClaudeAccount(id: "claude-a", alias: "work", email: "w***@example.com", weeklyUsedPercent: 35),
        ])
    }
}
