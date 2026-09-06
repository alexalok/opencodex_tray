import XCTest
@testable import OpenCodexQuotaCore

final class ConfigurationTests: XCTestCase {
    func testResolvesDefaultsWithoutAccountSelector() throws {
        let config = try TrayConfiguration.resolve(environment: [
            "HOME": "/Users/user",
        ])

        XCTAssertEqual(config.baseURL, URL(string: "http://127.0.0.1:10100")!)
        XCTAssertEqual(config.adminTokenPath, "/Users/user/.opencodex/admin-api-token")
        XCTAssertEqual(config.pollInterval, 60)
        XCTAssertEqual(config.requestTimeout, 30)
    }

    func testRejectsHTTPHostnameThatOnlyLooksLikeLoopback() {
        for hostname in ["127.attacker.example", "127.0.0.1.attacker.example"] {
            XCTAssertThrowsError(try TrayConfiguration.resolve(environment: [
                "HOME": "/tmp",
                "OPENCODEX_BASE_URL": "http://\(hostname)",
            ]))
        }
    }

    func testLoadsFinderSafeJSONConfigWithoutAccountSelector() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("config.json")
        try Data(#"{"pollIntervalMS":15000,"requestTimeoutMS":5000,"openCodexBaseURL":"https://opencodex.example","openCodexHome":"/tmp/opencodex"}"#.utf8).write(to: file)

        let config = try TrayConfiguration.load(
            environment: ["HOME": "/Users/user"],
            configFileURL: file
        )

        XCTAssertEqual(config.baseURL, URL(string: "https://opencodex.example")!)
        XCTAssertEqual(config.adminTokenPath, "/tmp/opencodex/admin-api-token")
        XCTAssertEqual(config.pollInterval, 15)
        XCTAssertEqual(config.requestTimeout, 5)
    }
}
