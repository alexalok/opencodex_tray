import Foundation
import XCTest
@testable import OpenCodexQuotaCore

final class QuotaConnectionTests: XCTestCase {
    private let host = URL(string: "http://127.0.0.1:10100")!
    private let config = Data(#"{"runtimeRole":"client","client":{"serverUrl":"https://hub.example","managementUrl":"https://hub.example","apiKeyId":"client-1","connectedAt":"2026-10-26T18:38:02.191Z","tokenFingerprint":"505a8c497606f899f72232a403399922417b7ca910dd96f341a44d1658a22a8f"}}"#.utf8)

    func testLocalRoleKeepsLocalCredentialAndDisabledProvider() throws {
        let connection = try QuotaConnection.resolve(hostURL: host, runningRole: "standalone",
            configData: Data(#"{"providers":{"anthropic":{"disabled":true}}}"#.utf8),
            adminToken: "local-admin", dataToken: nil)
        XCTAssertEqual(connection.mode, .local)
        XCTAssertEqual(connection.sourceURL, host)
        XCTAssertEqual(connection.token, "local-admin")
        XCTAssertFalse(connection.claudeEnabled)
    }

    func testRemovedProviderDoesNotShowRetainedAccounts() throws {
        let connection = try QuotaConnection.resolve(hostURL: host, runningRole: "standalone",
            configData: Data(#"{"providers":{"openai":{"disabled":false}}}"#.utf8),
            adminToken: "admin", dataToken: nil)
        XCTAssertTrue(connection.codexEnabled)
        XCTAssertFalse(connection.claudeEnabled)
    }

    func testHubRoleOnHostStillUsesLocalManagement() throws {
        let connection = try QuotaConnection.resolve(hostURL: host, runningRole: "hub",
            configData: Data(#"{"runtimeRole":"hub"}"#.utf8), adminToken: "admin", dataToken: nil)
        XCTAssertEqual(connection.mode, .local)
    }

    func testClientUsesOnlyFingerprintBoundDataKey() throws {
        let connection = try QuotaConnection.resolve(hostURL: host, runningRole: "client",
            configData: config, adminToken: "must-not-leave-host", dataToken: "hub-token")
        XCTAssertEqual(connection.mode, .hub)
        XCTAssertEqual(connection.sourceURL.absoluteString, "https://hub.example")
        XCTAssertEqual(connection.token, "hub-token")
        XCTAssertEqual(connection.apiKeyId, "client-1")
        XCTAssertFalse(String(data: try JSONEncoder().encode(connection), encoding: .utf8)!.contains("must-not-leave-host"))
    }

    func testWrongTokenAndRuntimeConfigMismatchFailWithoutLocalFallback() throws {
        XCTAssertThrowsError(try QuotaConnection.resolve(hostURL: host, runningRole: "client",
            configData: config, adminToken: "admin", dataToken: "wrong-key"))
        XCTAssertThrowsError(try QuotaConnection.resolve(hostURL: host, runningRole: "standalone",
            configData: config, adminToken: "admin", dataToken: "hub-token"))
        XCTAssertThrowsError(try QuotaConnection.resolve(hostURL: host, runningRole: "client",
            configData: Data("{}".utf8), adminToken: "admin", dataToken: "hub-token"))
    }

    func testRemoteHTTPAndCredentialURLsRejected() {
        for target in ["http://hub.example", "https://user:secret@hub.example", "https://hub.example/path", "https://hub.example?x=1"] {
            let data = Data(String(data: config, encoding: .utf8)!.replacingOccurrences(of: "https://hub.example", with: target).utf8)
            XCTAssertThrowsError(try QuotaConnection.resolve(hostURL: host, runningRole: "client",
                configData: data, adminToken: "admin", dataToken: "hub-token"), target)
        }
    }

    func testNextResolutionFollowsChangedTargetAndReturnToLocal() throws {
        let moved = Data(String(data: config, encoding: .utf8)!.replacingOccurrences(of: "hub.example", with: "new-hub.example").utf8)
        let remote = try QuotaConnection.resolve(hostURL: host, runningRole: "client", configData: moved, adminToken: nil, dataToken: "hub-token")
        XCTAssertEqual(remote.sourceURL.host, "new-hub.example")
        let local = try QuotaConnection.resolve(hostURL: host, runningRole: "standalone", configData: Data("{}".utf8), adminToken: "new-admin", dataToken: nil)
        XCTAssertEqual(local.mode, .local)
        XCTAssertEqual(local.token, "new-admin")
    }
}
