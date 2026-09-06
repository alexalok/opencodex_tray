import XCTest
import OpenCodexQuotaCore

final class QuotaWidgetStateTests: XCTestCase {
    func testCompleteLoadDisplaysLiveAndRequestsCacheReplacement() {
        let snapshot = makeCompleteSnapshot()
        let load = QuotaSnapshotLoad(snapshot: snapshot)

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
            load: QuotaSnapshotLoad(snapshot: partial),
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
            load: QuotaSnapshotLoad(snapshot: failed),
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
                load: QuotaSnapshotLoad(snapshot: failed),
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

    func testClaudeAccessibilityNamesBothPeriodsForFullValues() {
        let model = QuotaWidgetViewModel(
            content: .snapshot(makeCompleteSnapshot(), stale: false)
        )

        XCTAssertEqual(
            model.claude.accessibilityLabel,
            "Claude, 5-hour remaining: 97 percent; 1-week remaining: 88 percent"
        )
        XCTAssertEqual(
            model.claude.rows.map(\.accessibilityLabel),
            ["Claude work, 5-hour remaining: 97 percent; 1-week remaining: 88 percent"]
        )
        XCTAssertEqual(
            model.codex.accessibilityLabel,
            "Codex, remaining: 68 percent"
        )
        XCTAssertEqual(
            model.codex.rows.map(\.accessibilityLabel),
            ["Codex main, remaining: 68 percent of 100 percent"]
        )
    }

    func testClaudeAccessibilitySpeaksUnknownForPartialValues() {
        let claude = ClaudeQuotaSummary(
            fiveHourRemainingPercentage: nil,
            weeklyRemainingPercentage: 150,
            rows: [
                ClaudeAccountAllowance(
                    accountId: "claude-work",
                    label: "work",
                    fiveHourRemainingPercent: nil,
                    weeklyRemainingPercent: 62.5
                ),
            ]
        )
        let model = QuotaWidgetViewModel(
            content: .snapshot(
                makeSnapshot(codex: makeCodexSummary(), claude: claude),
                stale: false
            )
        )

        XCTAssertEqual(
            model.claude.accessibilityLabel,
            "Claude, 5-hour remaining: unknown; 1-week remaining: 150 percent"
        )
        XCTAssertEqual(
            model.claude.rows.map(\.accessibilityLabel),
            ["Claude work, 5-hour remaining: unknown; 1-week remaining: 62.5 percent"]
        )
    }

    func testUnavailableClaudeAccessibilityNamesProvider() {
        let partial = QuotaWidgetViewModel(
            content: .snapshot(makeCodexOnlySnapshot(), stale: false)
        )
        XCTAssertEqual(partial.claude.accessibilityLabel, "Claude, unavailable")

        let unavailable = QuotaWidgetViewModel(content: .unavailable)
        XCTAssertEqual(unavailable.claude.accessibilityLabel, "Claude, unavailable")
        XCTAssertEqual(unavailable.codex.accessibilityLabel, "Codex, unavailable")
    }

    func testUpdatedAgeTextDropsSecondsAndUsesEntryDate() {
        let entryDate = Date(timeIntervalSince1970: 10_000)

        let age = QuotaWidgetAgeText.make(
            updatedAt: entryDate.addingTimeInterval(-(5 * 60 + 42)),
            relativeTo: entryDate
        )

        XCTAssertEqual(age?.display, "5m ago")
        XCTAssertEqual(age?.accessibilityLabel, "Updated 5 minutes ago")
    }

    func testUpdatedAgeTextUsesStableWholeUnits() {
        let entryDate = Date(timeIntervalSince1970: 1_000_000)
        let cases: [(TimeInterval, String, String)] = [
            (30, "now", "Updated now"),
            (2 * 60, "2m ago", "Updated 2 minutes ago"),
            (3 * 60 * 60, "3h ago", "Updated 3 hours ago"),
            (4 * 24 * 60 * 60, "4d ago", "Updated 4 days ago"),
            (3 * 7 * 24 * 60 * 60, "3w ago", "Updated 3 weeks ago"),
        ]

        for (elapsed, display, accessibilityLabel) in cases {
            let age = QuotaWidgetAgeText.make(
                updatedAt: entryDate.addingTimeInterval(-elapsed),
                relativeTo: entryDate
            )
            XCTAssertEqual(age?.display, display)
            XCTAssertEqual(age?.accessibilityLabel, accessibilityLabel)
        }
    }

    func testUpdatedAgeTextHandlesMissingAndFutureDates() {
        let entryDate = Date(timeIntervalSince1970: 10_000)

        XCTAssertNil(QuotaWidgetAgeText.make(updatedAt: nil, relativeTo: entryDate))
        XCTAssertEqual(
            QuotaWidgetAgeText.make(
                updatedAt: entryDate.addingTimeInterval(60),
                relativeTo: entryDate
            )?.display,
            "now"
        )
    }
}
