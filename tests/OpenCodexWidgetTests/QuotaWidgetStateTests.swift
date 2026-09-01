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
}
