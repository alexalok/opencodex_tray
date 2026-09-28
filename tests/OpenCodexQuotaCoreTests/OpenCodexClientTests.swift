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
            case "/api/codex-auth/reset-credits":
                data = Data(#"{"credits":[]}"#.utf8)
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
            "GET /api/codex-auth/reset-credits?accountId=friend-id",
            "GET /api/oauth/accounts?provider=anthropic&quota=1&refresh=1",
        ])
        XCTAssertEqual(result.snapshot.codexSummary?.rows, [
            AccountAllowance(
                accountId: "friend-id",
                label: "workmate",
                remainingPercent: 7.5,
                totalPercent: 25,
                resetCreditExpirations: []
            ),
        ])
    }

    func testCreditLookupPreservesOrderAndQuotaWhenOneAccountFails() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: configuration)
        StubURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer admin-secret")
            var status = 200
            let data: Data
            if request.url?.path == "/api/codex-auth/accounts" {
                data = Data(#"{"accounts":[{"id":"paused & banked","paused":true,"quota":{"resetCredits":1}},{"id":"empty","quota":{"resetCredits":0}},{"id":"unknown","quota":{"weeklyPercent":30}}]}"#.utf8)
            } else {
                XCTAssertEqual(request.url?.path, "/api/codex-auth/reset-credits")
                let id = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first?.value
                if id == "paused & banked" || id == "empty" {
                    data = Data(#"{"credits":[{"expires_at":"2027-01-17T09:00:00Z"}]}"#.utf8)
                } else {
                    XCTAssertEqual(id, "unknown")
                    status = 503
                    data = Data()
                }
            }
            return (HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, data)
        }
        let client = OpenCodexClient(baseURL: URL(string: "https://opencodex.example")!,
                                    adminToken: "admin-secret", timeout: 5, session: session)
        let accounts = try await client.fetchAccounts()
        XCTAssertEqual(accounts.map(\.id), ["paused & banked", "empty", "unknown"])
        XCTAssertEqual(accounts[0].resetCreditExpirations?.count, 1)
        // A cached zero must not suppress the authoritative credit lookup.
        XCTAssertEqual(accounts[1].resetCreditExpirations?.count, 1)
        XCTAssertNil(accounts[2].resetCreditExpirations)
        XCTAssertEqual(accounts[2].weeklyUsedPercent, 30)
        XCTAssertEqual(StubURLProtocol.requests().count, 4)
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
