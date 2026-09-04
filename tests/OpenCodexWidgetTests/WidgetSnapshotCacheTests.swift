import Foundation
import XCTest

final class WidgetSnapshotCacheTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: temporaryDirectory)
        temporaryDirectory = nil
    }

    func testSaveThenLoadRoundTripsCompleteSnapshot() async throws {
        let cache = WidgetSnapshotCache(
            fileURL: temporaryDirectory.appendingPathComponent("quota.json")
        )
        let snapshot = makeCompleteSnapshot()

        try await cache.save(snapshot)
        let loaded = await cache.load()

        XCTAssertEqual(loaded, snapshot)
    }

    func testCorruptCacheIsMiss() async throws {
        let url = temporaryDirectory.appendingPathComponent("quota.json")
        try Data("not json".utf8).write(to: url)
        let cache = WidgetSnapshotCache(fileURL: url)
        let loaded = await cache.load()

        XCTAssertNil(loaded)
    }
}
