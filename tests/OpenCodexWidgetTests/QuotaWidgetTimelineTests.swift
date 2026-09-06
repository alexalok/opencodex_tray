import Foundation
import XCTest
import OpenCodexQuotaCore

final class QuotaWidgetTimelineTests: XCTestCase {
    func testNextRefreshIsThirtyMinutesAfterEntryDate() async {
        let now = Date(timeIntervalSince1970: 1_788_231_600)
        let service = QuotaWidgetTimelineService(
            makeLoader: { FakeSnapshotLoader(result: makeCompleteLoad()) },
            cache: FakeWidgetCache(),
            now: { now }
        )

        let result = await service.makeEntry()

        XCTAssertEqual(result.entry.date, now)
        XCTAssertEqual(result.nextRefresh, now.addingTimeInterval(30 * 60))
    }

    func testFactoryFailureUsesCachedSnapshotAsStale() async {
        let cached = makeCompleteSnapshot()
        let service = QuotaWidgetTimelineService(
            makeLoader: { throw ConfigurationError.invalid("Config unavailable") },
            cache: FakeWidgetCache(snapshot: cached),
            now: { widgetTestDate }
        )

        let result = await service.makeEntry()

        XCTAssertEqual(result.entry.content, .snapshot(cached, stale: true))
    }

    func testCompleteLoadWritesLastCompleteCache() async {
        let snapshot = makeCompleteSnapshot()
        let cache = FakeWidgetCache()
        let service = QuotaWidgetTimelineService(
            makeLoader: {
                FakeSnapshotLoader(
                    result: QuotaSnapshotLoad(snapshot: snapshot)
                )
            },
            cache: cache,
            now: { widgetTestDate }
        )

        let result = await service.makeEntry()
        let saves = await cache.saves()

        XCTAssertEqual(result.entry.content, .snapshot(snapshot, stale: false))
        XCTAssertEqual(saves, [snapshot])
    }

    func testPartialLoadDoesNotReplaceLastCompleteCache() async {
        let cached = makeCompleteSnapshot()
        let partial = makeSnapshot(
            codex: makeCodexSummary(),
            claude: nil,
            claudeError: "Claude unavailable"
        )
        let cache = FakeWidgetCache(snapshot: cached)
        let service = QuotaWidgetTimelineService(
            makeLoader: {
                FakeSnapshotLoader(
                    result: QuotaSnapshotLoad(snapshot: partial)
                )
            },
            cache: cache,
            now: { widgetTestDate }
        )

        let result = await service.makeEntry()
        let saves = await cache.saves()

        XCTAssertEqual(result.entry.content, .snapshot(partial, stale: false))
        XCTAssertEqual(saves, [])
    }

    func testGallerySnapshotUsesCachedDataAsStale() async {
        let cached = makeCompleteSnapshot()
        let cache = FakeWidgetCache(snapshot: cached)
        let provider = QuotaWidgetTimelineProvider(
            service: QuotaWidgetTimelineService(
                makeLoader: { throw ConfigurationError.invalid("must not run") },
                cache: cache,
                now: { widgetTestDate }
            ),
            cache: cache
        )

        let entry = await provider.snapshotEntry(at: widgetTestDate)

        XCTAssertEqual(entry.content, .snapshot(cached, stale: true))
        XCTAssertFalse(entry.isPlaceholder)
    }

    func testGallerySnapshotWithoutCacheUsesStaticPlaceholder() async {
        let cache = FakeWidgetCache()
        let provider = QuotaWidgetTimelineProvider(
            service: QuotaWidgetTimelineService(
                makeLoader: { throw ConfigurationError.invalid("must not run") },
                cache: cache,
                now: { widgetTestDate }
            ),
            cache: cache
        )

        let entry = await provider.snapshotEntry(at: widgetTestDate)

        XCTAssertTrue(entry.isPlaceholder)
        guard case let .snapshot(snapshot, stale) = entry.content else {
            return XCTFail("Expected representative placeholder snapshot")
        }
        XCTAssertFalse(stale)
        XCTAssertEqual(snapshot.codexSummary?.trayPercentage, 68)
        XCTAssertEqual(snapshot.claudeSummary?.fiveHourRemainingPercentage, 97)
        XCTAssertEqual(snapshot.claudeSummary?.weeklyRemainingPercentage, 88)
    }
}
