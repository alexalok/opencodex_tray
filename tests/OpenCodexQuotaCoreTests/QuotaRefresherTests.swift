import Foundation
import XCTest
@testable import OpenCodexQuotaCore

private actor FakeSnapshotLoader: QuotaSnapshotLoading {
    let result: QuotaSnapshotLoad
    let delay: Duration?
    private var callCount = 0

    init(result: QuotaSnapshotLoad, delay: Duration? = nil) {
        self.result = result
        self.delay = delay
    }

    func load() async -> QuotaSnapshotLoad {
        callCount += 1
        if let delay { try? await Task.sleep(for: delay) }
        return result
    }

    func calls() -> Int { callCount }
}

private let refresherTestSnapshot = QuotaSnapshot(
    fetchedAt: Date(timeIntervalSince1970: 1_788_231_600),
    codexSummary: QuotaSummary(trayPercentage: 80, rows: []),
    codexErrorMessage: nil,
    claudeSummary: ClaudeQuotaSummary(
        fiveHourRemainingPercentage: 90,
        weeklyRemainingPercentage: 70,
        rows: []
    ),
    claudeErrorMessage: nil
)

final class QuotaRefresherTests: XCTestCase {
    func testConcurrentRefreshesCoalesceIntoOneSnapshotLoad() async {
        let expected = QuotaSnapshotLoad(snapshot: refresherTestSnapshot)
        let loader = FakeSnapshotLoader(result: expected, delay: .milliseconds(50))
        let refresher = QuotaRefresher(loader: loader)

        async let first = refresher.refresh()
        async let second = refresher.refresh()
        let results = await [first, second]
        let callCount = await loader.calls()

        XCTAssertEqual(results, [expected, expected])
        XCTAssertEqual(callCount, 1)
    }
}
