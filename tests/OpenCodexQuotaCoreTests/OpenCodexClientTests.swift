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

        let result = try await QuotaRefresher(client: client).refresh()

        XCTAssertEqual(StubURLProtocol.requests().sorted(), [
            "GET /api/codex-auth/accounts?refresh=1",
            "GET /api/oauth/accounts?provider=anthropic&quota=1&refresh=1",
        ])
        XCTAssertEqual(result.codexSummary.rows, [
            AccountAllowance(
                accountId: "friend-id",
                label: "workmate",
                remainingPercent: 7.5,
                totalPercent: 25
            ),
        ])
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
