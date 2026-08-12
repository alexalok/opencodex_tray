import XCTest
@testable import PauseWorkerCore

final class ConfigurationTests: XCTestCase {
    func testResolvesExistingWorkerDefaults() throws {
        let config = try WorkerConfiguration.resolve(environment: [
            "HOME": "/Users/user",
            "TARGET_ACCOUNT_ALIAS": "workmate",
        ])

        XCTAssertEqual(config.baseURL, URL(string: "http://127.0.0.1:10100")!)
        XCTAssertEqual(config.adminTokenPath, "/Users/user/.opencodex/admin-api-token")
        XCTAssertEqual(config.targetAlias, "workmate")
        XCTAssertEqual(config.thresholdPercent, 70)
        XCTAssertEqual(config.pollInterval, 60)
        XCTAssertEqual(config.requestTimeout, 30)
    }

    func testPreservesAliasForExactMatching() throws {
        let config = try WorkerConfiguration.resolve(environment: [
            "HOME": "/tmp",
            "TARGET_ACCOUNT_ALIAS": " friend ",
        ])
        XCTAssertEqual(config.targetAlias, " friend ")
    }

    func testRejectsLegacyIDSelector() {
        XCTAssertThrowsError(try WorkerConfiguration.resolve(environment: [
            "HOME": "/tmp",
            "TARGET_ACCOUNT_ALIAS": "friend",
            "TARGET_ACCOUNT_ID": "id",
        ]))
    }

    func testRejectsHTTPHostnameThatOnlyLooksLikeLoopback() {
        for hostname in ["127.attacker.example", "127.0.0.1.attacker.example"] {
            XCTAssertThrowsError(try WorkerConfiguration.resolve(environment: [
                "HOME": "/tmp",
                "TARGET_ACCOUNT_ALIAS": "friend",
                "OPENCODEX_BASE_URL": "http://\(hostname)",
            ]))
        }
    }

    func testLoadsFinderSafeJSONConfigWhenEnvironmentHasNoAlias() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("config.json")
        try Data(#"{"targetAccountAlias":"workmate","pauseThresholdPercent":70}"#.utf8).write(to: file)

        let config = try WorkerConfiguration.load(
            environment: ["HOME": "/Users/user"],
            configFileURL: file
        )

        XCTAssertEqual(config.targetAlias, "workmate")
        XCTAssertEqual(config.thresholdPercent, 70)
    }
}
