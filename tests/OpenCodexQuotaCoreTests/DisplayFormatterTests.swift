import Foundation
import XCTest
@testable import OpenCodexQuotaCore

final class DisplayFormatterTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func at(_ seconds: TimeInterval) -> Double { (now.timeIntervalSince1970 + seconds) * 1_000 }

    func testPercentFloors() {
        XCTAssertEqual(DisplayFormatter.percent(38.99), "38%")
        XCTAssertEqual(DisplayFormatter.percent(-1), "0%")
    }

    func testUsageOmitsAbsentFiveHourWindow() {
        let five = TrayQuotaWindow(remainingPercent: 30.4)
        let week = TrayQuotaWindow(remainingPercent: 90.9)
        XCTAssertEqual(DisplayFormatter.usage(fiveHour: five, weekly: week), "30%/90%")
        XCTAssertEqual(DisplayFormatter.usage(fiveHour: nil, weekly: week), "90%")
        XCTAssertNil(DisplayFormatter.usage(fiveHour: nil, weekly: nil))
    }

    func testDurations() {
        XCTAssertEqual(DisplayFormatter.duration(untilMilliseconds: at(90 * 60), now: now), "1h30m")
        XCTAssertEqual(DisplayFormatter.duration(untilMilliseconds: at(4 * 3_600 + 9 * 60), now: now), "4h9m")
        XCTAssertEqual(DisplayFormatter.duration(untilMilliseconds: at(2 * 86_400 + 3 * 3_600), now: now), "2d3h")
        XCTAssertEqual(DisplayFormatter.duration(untilMilliseconds: at(2 * 86_400 + 3 * 3_600), now: now, spaced: true), "2d 3h")
        XCTAssertEqual(DisplayFormatter.duration(untilMilliseconds: at(5 * 60), now: now), "5m")
        XCTAssertEqual(DisplayFormatter.duration(untilMilliseconds: at(-60), now: now), "0m")
    }

    func testAccountNameStopsAtFirstSpaceOrTenCharacters() {
        XCTAssertEqual(DisplayFormatter.accountName("Work Pro"), "Work")
        XCTAssertEqual(DisplayFormatter.accountName("averyverylongname@example.com"), "averyveryl")
        XCTAssertEqual(DisplayFormatter.accountName("main"), "main")
    }

    func testAccountRowShowsPlanUnitsAndRemaining() {
        let account = TrayQuotaAccount(name: "alex@example.com", plan: "prolite", units: 10,
            fiveHour: TrayQuotaWindow(remainingPercent: 30), weekly: TrayQuotaWindow(remainingPercent: 90))
        XCTAssertEqual(DisplayFormatter.accountRow(account), "alex@examp [prolite x10] 30%/90%")
        let weeklyOnly = TrayQuotaAccount(name: "Plus", plan: "plus", units: 1, weekly: TrayQuotaWindow(remainingPercent: 7))
        XCTAssertEqual(DisplayFormatter.accountRow(weeklyOnly), "Plus [plus x1] 7%")
        XCTAssertEqual(DisplayFormatter.accountRow(TrayQuotaAccount(name: "main", state: "reauth")), "main reauth –")
    }

    func testResetCreditsShowCountAndSoonestExpiry() {
        let account = TrayQuotaAccount(name: "a", resetCredits: TrayQuotaResetCredits(count: 2, soonestExpiresAt: at(2 * 86_400 + 3 * 3_600)))
        XCTAssertEqual(DisplayFormatter.resetCredits(account, now: now), "x2, 2d3h")
        XCTAssertEqual(DisplayFormatter.resetCredits(TrayQuotaAccount(name: "a", resetCredits: TrayQuotaResetCredits(count: 1)), now: now), "x1")
        XCTAssertNil(DisplayFormatter.resetCredits(TrayQuotaAccount(name: "a", resetCredits: TrayQuotaResetCredits(count: 0)), now: now))
        XCTAssertNil(DisplayFormatter.resetCredits(TrayQuotaAccount(name: "a"), now: now))
    }

    func testRecoveryRow() {
        let both = TrayQuotaProvider(provider: "openai",
            fiveHour: TrayQuotaWindow(remainingPercent: 50, nextRecoveryAt: at(90 * 60), nextRecoveryPercent: 30.7),
            weekly: TrayQuotaWindow(remainingPercent: 40, nextRecoveryAt: at(4 * 3_600 + 9 * 60), nextRecoveryPercent: 10))
        XCTAssertEqual(DisplayFormatter.recovery(both, now: now), "5h/7d recovery: 1h30m (+30%) | 4h9m (+10%)")
        let weekly = TrayQuotaProvider(provider: "openai",
            weekly: TrayQuotaWindow(remainingPercent: 40, nextRecoveryAt: at(7 * 3_600), nextRecoveryPercent: 10))
        XCTAssertEqual(DisplayFormatter.recovery(weekly, now: now), "7d recovery: 7h0m (+10%)")
        XCTAssertNil(DisplayFormatter.recovery(TrayQuotaProvider(provider: "openai", weekly: TrayQuotaWindow(remainingPercent: 100)), now: now))
    }
}
