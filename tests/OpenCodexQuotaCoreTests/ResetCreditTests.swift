import Foundation
import XCTest
@testable import OpenCodexQuotaCore

final class ResetCreditTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testWarningUsesStrictSevenDayWindowAndEarliestUnexpiredCredit() {
        let expirations = [-1.0, 0, 7 * 86400, 7 * 86400 - 1, 3600].map { now.addingTimeInterval($0) }
        let row = AccountAllowance(accountId: "a", label: "work", paused: true,
                                   remainingPercent: nil, totalPercent: nil,
                                   resetCreditExpirations: expirations)
        XCTAssertEqual(row.expiringReset(at: now), now.addingTimeInterval(3600))
        XCTAssertEqual(DisplayFormatter.resetExpiry(row, now: now), "exp in 1h")
        for interval: Double in [-1, 0, 7 * 86400, 8 * 86400] {
            let outside = AccountAllowance(accountId: "a", label: "work", remainingPercent: nil,
                                           totalPercent: nil, resetCreditExpirations: [now.addingTimeInterval(interval)])
            XCTAssertNil(outside.expiringReset(at: now))
        }
    }

    func testCountdownUnits() {
        for (seconds, expected) in [(1.0, "exp in <1m"), (61, "exp in 1m"),
                                    (3660, "exp in 1h 1m"), (183600, "exp in 2d 3h")] {
            let row = AccountAllowance(accountId: "a", label: "work", remainingPercent: nil,
                                       totalPercent: nil, resetCreditExpirations: [now.addingTimeInterval(seconds)])
            XCTAssertEqual(DisplayFormatter.resetExpiry(row, now: now), expected)
        }
    }

    func testDecodesCreditDatesAndIgnoresInvalidDates() throws {
        let data = Data(#"{"credits":[{"expires_at":"2027-01-17T09:00:00Z"},{"expires_at":"2027-01-18T09:00:00.123Z"},{"expires_at":"invalid"}]}"#.utf8)
        let dates = try OpenCodexResponseDecoder.decodeResetCreditExpirations(data)
        XCTAssertEqual(dates.count, 2)
        XCTAssertEqual(dates[1].timeIntervalSince(dates[0]), 86400.123, accuracy: 0.001)
        XCTAssertEqual(try OpenCodexResponseDecoder.decodeResetCreditExpirations(Data(#"{"available_count":0,"credits":[{"expires_at":"2027-01-17T09:00:00Z"}]}"#.utf8)), [])
    }

    func testLegacySnapshotAndExpiryRoundTrip() throws {
        let old = Data(#"{"accountId":"a","label":"work","remainingPercent":50,"totalPercent":100}"#.utf8)
        XCTAssertNil(try JSONDecoder().decode(AccountAllowance.self, from: old).resetCreditExpirations)
        let account = OpenCodexAccount(id: "a", alias: "work", plan: "pro", isMain: false,
                                      weeklyUsedPercent: 50, resetCreditExpirations: [now])
        let row = try XCTUnwrap(QuotaCalculator.summarize(accounts: [account]).rows.first)
        XCTAssertEqual(row.resetCreditExpirations, [now])
        XCTAssertEqual(try JSONDecoder().decode(AccountAllowance.self, from: JSONEncoder().encode(row)), row)
    }
}
