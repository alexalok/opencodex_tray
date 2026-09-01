import XCTest
import PauseWorkerCore

final class QuotaWidgetStateTests: XCTestCase {
    func testCompleteLoadDisplaysLiveAndRequestsCacheReplacement() {
        let snapshot = makeCompleteSnapshot()
        let load = QuotaSnapshotLoad(snapshot: snapshot, codexAccounts: [])

        let result = QuotaWidgetStateResolver.resolve(load: load, cached: nil)

        XCTAssertEqual(result.content, .snapshot(snapshot, stale: false))
        XCTAssertEqual(result.snapshotToCache, snapshot)
    }

    func testPartialLoadDisplaysUnavailableProviderAndPreservesCache() {
        let cached = makeCompleteSnapshot()
        let partial = makeSnapshot(
            codex: makeCodexSummary(),
            codexError: nil,
            claude: nil,
            claudeError: "Claude unavailable"
        )

        let result = QuotaWidgetStateResolver.resolve(
            load: QuotaSnapshotLoad(snapshot: partial, codexAccounts: []),
            cached: cached
        )

        XCTAssertEqual(result.content, .snapshot(partial, stale: false))
        XCTAssertNil(result.snapshotToCache)
    }

    func testTotalFailureUsesStaleCache() {
        let cached = makeCompleteSnapshot()
        let failed = makeSnapshot(
            codex: nil,
            codexError: "Codex unavailable",
            claude: nil,
            claudeError: "Claude unavailable"
        )

        let result = QuotaWidgetStateResolver.resolve(
            load: QuotaSnapshotLoad(snapshot: failed, codexAccounts: nil),
            cached: cached
        )

        XCTAssertEqual(result.content, .snapshot(cached, stale: true))
        XCTAssertNil(result.snapshotToCache)
    }

    func testTotalFailureWithoutCacheIsUnavailable() {
        let failed = makeSnapshot(
            codex: nil,
            codexError: "Codex unavailable",
            claude: nil,
            claudeError: "Claude unavailable"
        )

        XCTAssertEqual(
            QuotaWidgetStateResolver.resolve(
                load: QuotaSnapshotLoad(snapshot: failed, codexAccounts: nil),
                cached: nil
            ).content,
            .unavailable
        )
    }

    func testConfigurationFailureWithoutCacheIsUnavailable() {
        XCTAssertEqual(
            QuotaWidgetStateResolver.resolve(load: nil, cached: nil).content,
            .unavailable
        )
    }

    func testMediumModelCapsRowsAtTwoAndReportsOverflow() {
        let model = QuotaWidgetViewModel(
            content: .snapshot(makeThreeAccountSnapshot(), stale: false)
        )

        XCTAssertEqual(model.claude.total, "281%/256%")
        XCTAssertEqual(model.claude.rows.map(\.label), ["work", "personal"])
        XCTAssertEqual(model.claude.rows.map(\.value), ["97% / 88%", "94% / 88%"])
        XCTAssertEqual(model.claude.overflowCount, 1)
        XCTAssertEqual(model.codex.total, "94%")
        XCTAssertEqual(model.codex.rows.map(\.label), ["main", "workmate"])
        XCTAssertEqual(model.codex.rows.map(\.value), ["68% / 100%", "16% / 17.5%"])
        XCTAssertEqual(model.codex.overflowCount, 1)
    }

    func testPartialModelMarksOnlyMissingProviderUnavailable() {
        let model = QuotaWidgetViewModel(
            content: .snapshot(makeCodexOnlySnapshot(), stale: false)
        )

        XCTAssertFalse(model.codex.isUnavailable)
        XCTAssertTrue(model.claude.isUnavailable)
    }

    func testSnapshotModelPreservesTimestampAndStaleMarker() {
        let snapshot = makeCompleteSnapshot()

        let model = QuotaWidgetViewModel(content: .snapshot(snapshot, stale: true))

        XCTAssertEqual(model.updatedAt, widgetTestDate)
        XCTAssertTrue(model.isStale)
        XCTAssertFalse(model.isUnavailable)
    }

    func testUnavailableModelHasNoTimestampOrRows() {
        let model = QuotaWidgetViewModel(content: .unavailable)

        XCTAssertNil(model.updatedAt)
        XCTAssertTrue(model.isUnavailable)
        XCTAssertTrue(model.codex.rows.isEmpty)
        XCTAssertTrue(model.claude.rows.isEmpty)
    }
}
