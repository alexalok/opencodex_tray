import Foundation
import XCTest
@testable import OpenCodexQuotaCore

private actor FakeLoader: TrayQuotaLoading {
    let result: TrayQuotaLoad
    private var callCount = 0

    init(result: TrayQuotaLoad) { self.result = result }

    func load() async -> TrayQuotaLoad {
        callCount += 1
        try? await Task.sleep(for: .milliseconds(50))
        return result
    }

    func calls() -> Int { callCount }
}

final class QuotaRefresherTests: XCTestCase {
    func testConcurrentRefreshesCoalesceIntoOneLoad() async {
        let expected = TrayQuotaLoad(quota: TrayQuota(generatedAt: 0, providers: []), sourceLabel: "Local OpenCodex")
        let loader = FakeLoader(result: expected)
        let refresher = QuotaRefresher(loader: loader)

        async let first = refresher.refresh()
        async let second = refresher.refresh()
        let results = await [first, second]
        let callCount = await loader.calls()

        XCTAssertEqual(results, [expected, expected])
        XCTAssertEqual(callCount, 1)
    }
}
