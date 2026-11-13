import Foundation
import XCTest
@testable import OpenCodexQuotaCore

final class TrayLabelPlannerTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private func minute(_ n: Int) -> Date { start.addingTimeInterval(TimeInterval(n) * 60) }

    private func quota(_ providers: TrayQuotaProvider...) -> TrayQuota {
        TrayQuota(generatedAt: 0, providers: providers)
    }
    private func codex(_ five: Double?, _ week: Double) -> TrayQuotaProvider {
        TrayQuotaProvider(provider: "openai", fiveHour: five.map { TrayQuotaWindow(remainingPercent: $0) },
                          weekly: TrayQuotaWindow(remainingPercent: week))
    }

    func testAmpleQuotaIsNeverShown() {
        var planner = TrayLabelPlanner()
        XCTAssertEqual(planner.update(quota(codex(99, 96)), now: minute(0)), [])
    }

    func testSlowPollingStillTicksEveryMinute() {
        var every = TrayTickSchedule(pollInterval: 60)
        XCTAssertEqual((0..<3).map { _ in every.next() }, [true, true, true])
        var slow = TrayTickSchedule(pollInterval: 300)
        XCTAssertEqual((0..<11).map { _ in slow.next() }, [true, false, false, false, false, true, false, false, false, false, true])
        var odd = TrayTickSchedule(pollInterval: 90)
        XCTAssertEqual((0..<4).map { _ in odd.next() }, [true, false, true, false])

        // Between reads the planner replays the held quota, so a change still hides after ten minutes.
        var planner = TrayLabelPlanner()
        let held = quota(codex(39.5, 99))
        XCTAssertEqual(planner.update(held, now: minute(0)).count, 1)
        XCTAssertEqual(planner.update(held, now: minute(9)).count, 1)
        XCTAssertEqual(planner.update(held, now: minute(10)), [])
    }

    func testChangeIsShownForTenMinutesThenHidden() {
        var planner = TrayLabelPlanner()
        XCTAssertEqual(planner.update(quota(codex(39.5, 99)), now: minute(0)), [TrayLabelItem(provider: "openai", text: "39%/99%")])
        XCTAssertEqual(planner.update(quota(codex(39.1, 99)), now: minute(9)), [TrayLabelItem(provider: "openai", text: "39%/99%")])
        XCTAssertEqual(planner.update(quota(codex(39.1, 99)), now: minute(10)), [], "same floored value does not extend the window")
        XCTAssertEqual(planner.update(quota(codex(38.9, 99)), now: minute(11)), [TrayLabelItem(provider: "openai", text: "38%/99%")])
        XCTAssertEqual(planner.update(quota(codex(38.9, 99)), now: minute(20)), [TrayLabelItem(provider: "openai", text: "38%/99%")])
        XCTAssertEqual(planner.update(quota(codex(38.9, 99)), now: minute(21)), [])
    }

    func testFirstDipBelowThresholdIsShownAgainAfterRecovery() {
        var planner = TrayLabelPlanner()
        XCTAssertEqual(planner.update(quota(codex(94, 99)), now: minute(0)).count, 1)
        XCTAssertEqual(planner.update(quota(codex(94, 99)), now: minute(10)), [])
        XCTAssertEqual(planner.update(quota(codex(100, 99)), now: minute(11)), [])
        XCTAssertEqual(planner.update(quota(codex(94, 99)), now: minute(12)), [TrayLabelItem(provider: "openai", text: "94%/99%")])
    }

    func testWeeklyOnlyProviderShowsSingleValue() {
        var planner = TrayLabelPlanner()
        XCTAssertEqual(planner.update(quota(codex(nil, 50)), now: minute(0)), [TrayLabelItem(provider: "openai", text: "50%")])
    }

    func testBlockedProviderStaysShownWithCountdownAndResetIcon() {
        var planner = TrayLabelPlanner()
        let recoversAt = (minute(0).timeIntervalSince1970 + 2 * 86_400 + 3 * 3_600) * 1_000
        let weekly = TrayQuotaProvider(provider: "openai", fiveHour: TrayQuotaWindow(remainingPercent: 50),
            weekly: TrayQuotaWindow(remainingPercent: 0), blocked: TrayQuotaBlock(window: "weekly", recoversAt: recoversAt), resetCredits: 1)
        XCTAssertEqual(planner.update(quota(weekly), now: minute(0)),
                       [TrayLabelItem(provider: "openai", text: "0%/0% 2d 3h", showsResetIcon: true)])
        XCTAssertEqual(planner.update(quota(weekly), now: minute(5)).first?.text, "0%/0% 2d 2h")

        let burst = TrayQuotaProvider(provider: "anthropic", fiveHour: TrayQuotaWindow(remainingPercent: 0),
            weekly: TrayQuotaWindow(remainingPercent: 40),
            blocked: TrayQuotaBlock(window: "5h", recoversAt: (minute(0).timeIntervalSince1970 + 90 * 60) * 1_000), resetCredits: 3)
        XCTAssertEqual(planner.update(quota(burst), now: minute(0)), [TrayLabelItem(provider: "anthropic", text: "0%/0% 1h30m")])
    }

    func testFailedReadShowsNothing() {
        var planner = TrayLabelPlanner()
        XCTAssertEqual(planner.update(nil, now: minute(0)), [])
    }
}
