import Foundation
import XCTest
@testable import PauseWorkerCore

private final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
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
        super.tearDown()
    }

    func testFetchClaudeAccountsUsesAnthropicPerAccountWeeklyQuotaEndpoint() async throws {
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
