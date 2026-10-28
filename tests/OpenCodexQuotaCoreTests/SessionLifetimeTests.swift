import Foundation
import XCTest
@testable import OpenCodexQuotaCore

private final class LifetimeDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {
    let invalidated: XCTestExpectation
    init(_ invalidated: XCTestExpectation) { self.invalidated = invalidated }
    func urlSession(_ session: URLSession, didBecomeInvalidWithError error: (any Error)?) {
        invalidated.fulfill()
    }
}

final class SessionLifetimeTests: XCTestCase {
    func testLocalClientInvalidatesItsOwnedSessionOnRelease() async {
        let invalidated = expectation(description: "owned session invalidated")
        let session = URLSession(configuration: .ephemeral, delegate: LifetimeDelegate(invalidated), delegateQueue: nil)
        var client: OpenCodexClient? = OpenCodexClient(baseURL: URL(string: "http://localhost:10100")!,
            adminToken: "fixture", timeout: 1, session: session, ownsSession: true)
        XCTAssertNotNil(client)
        client = nil
        await fulfillment(of: [invalidated], timeout: 2)
    }

    func testBorrowedSessionRemainsUsableUntilCallerInvalidatesIt() async {
        let invalidated = expectation(description: "caller invalidates borrowed session")
        let session = URLSession(configuration: .ephemeral, delegate: LifetimeDelegate(invalidated), delegateQueue: nil)
        var client: OpenCodexClient? = OpenCodexClient(baseURL: URL(string: "http://localhost:10100")!,
            adminToken: "fixture", timeout: 1, session: session)
        XCTAssertNotNil(client)
        client = nil
        session.finishTasksAndInvalidate()
        await fulfillment(of: [invalidated], timeout: 2)
    }
}
