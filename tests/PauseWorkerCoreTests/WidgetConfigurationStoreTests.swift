import Foundation
import XCTest
@testable import PauseWorkerCore

final class WidgetConfigurationStoreTests: XCTestCase {
    func testRoundTripsWidgetConnectionConfigurationWithPrivatePermissions() throws {
        let container = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: container) }
        let store = WidgetConfigurationStore(containerURL: container)
        let configuration = WidgetConnectionConfiguration(
            baseURL: URL(string: "http://127.0.0.1:10100")!,
            adminToken: "secret-token",
            targetAlias: "workmate",
            thresholdPercent: 70,
            requestTimeout: 30
        )

        try store.save(configuration)

        XCTAssertEqual(try store.load(), configuration)
        let attributes = try FileManager.default.attributesOfItem(
            atPath: store.fileURL.path
        )
        XCTAssertEqual(
            (attributes[.posixPermissions] as? NSNumber)?.intValue,
            0o600
        )
    }

    func testUsesTeamScopedMacOSAppGroup() {
        XCTAssertEqual(
            WidgetConfigurationStore.appGroupIdentifier,
            "KTNPDHXXV3.opencodex.quota-tray.shared"
        )
    }
}
