import Foundation
import XCTest
@testable import OpenCodexQuotaCore

final class TrayVisibilityTests: XCTestCase {
    private func codex(_ id: String, plan: String = "pro", paused: Bool = false, weekly: Double?, fiveHour: Double?,
                       threshold: Double? = nil) -> OpenCodexAccount {
        OpenCodexAccount(id: id, alias: id, plan: plan, isMain: false, paused: paused,
            weeklyUsedPercent: weekly, fiveHourUsedPercent: fiveHour, autoSwitchThreshold: threshold)
    }

    func testCodexHidesOnlyWhenBothUnroundedPoolTotalsExceedThreshold() {
        XCTAssertTrue(QuotaCalculator.summarize(accounts: [codex("a", weekly: 0, fiveHour: 0)]).hideFromTray)
        XCTAssertTrue(QuotaCalculator.summarize(accounts: [codex("a", weekly: 4.9999, fiveHour: 4.9999)]).hideFromTray)
        // Exactly 95 remaining is not above the threshold; display rounding is irrelevant.
        XCTAssertFalse(QuotaCalculator.summarize(accounts: [codex("a", weekly: 5, fiveHour: 0)]).hideFromTray)
        XCTAssertFalse(QuotaCalculator.summarize(accounts: [codex("a", weekly: 0, fiveHour: 5)]).hideFromTray)
        XCTAssertFalse(QuotaCalculator.summarize(accounts: [codex("a", weekly: 30, fiveHour: 0)]).hideFromTray)
        XCTAssertFalse(QuotaCalculator.summarize(accounts: [codex("a", weekly: 0, fiveHour: 30)]).hideFromTray)
    }

    func testCodexPoolTotalsUseExistingProEquivalentUnitsAndThresholds() {
        // Pool totals are absolute across accounts, so several partially used accounts can still hide.
        XCTAssertTrue(QuotaCalculator.summarize(accounts: [
            codex("a", weekly: 40, fiveHour: 40), codex("b", weekly: 40, fiveHour: 40),
        ]).hideFromTray)
        // A single Plus account tops out at 5 Pro-equivalent points.
        XCTAssertFalse(QuotaCalculator.summarize(accounts: [codex("plus", plan: "plus", weekly: 0, fiveHour: 0)]).hideFromTray)
        // Auto-switch thresholds cap both windows at the native allowance OpenCodex will actually use.
        XCTAssertFalse(QuotaCalculator.summarize(accounts: [codex("a", weekly: 0, fiveHour: 0, threshold: 80)]).hideFromTray)
        XCTAssertTrue(QuotaCalculator.summarize(accounts: [
            codex("a", weekly: 0, fiveHour: 0, threshold: 80), codex("b", weekly: 0, fiveHour: 0, threshold: 80),
        ]).hideFromTray)
        XCTAssertEqual(QuotaCalculator.summarize(accounts: [codex("a", weekly: 10, fiveHour: 20, threshold: 80)])
            .rows.first?.fiveHourRemainingPercent, 60)
    }

    func testCodexStaysVisibleWhenAnyActiveWindowIsUnknown() {
        XCTAssertFalse(QuotaCalculator.summarize(accounts: [codex("a", weekly: 0, fiveHour: nil)]).hideFromTray)
        XCTAssertFalse(QuotaCalculator.summarize(accounts: [codex("a", weekly: nil, fiveHour: 0)]).hideFromTray)
        XCTAssertFalse(QuotaCalculator.summarize(accounts: [
            codex("a", weekly: 0, fiveHour: 0), codex("b", weekly: 0, fiveHour: nil),
        ]).hideFromTray)
        XCTAssertFalse(QuotaCalculator.summarize(accounts: [codex("a", plan: "future", weekly: 0, fiveHour: 0)]).hideFromTray)
        XCTAssertFalse(QuotaCalculator.summarize(accounts: []).hideFromTray)
    }

    func testPausedCodexAccountsNeitherContributeNorBlockHiding() {
        XCTAssertTrue(QuotaCalculator.summarize(accounts: [
            codex("a", weekly: 0, fiveHour: 0), codex("b", paused: true, weekly: 100, fiveHour: nil),
        ]).hideFromTray)
        // An entirely paused pool shows 0% and must stay visible.
        XCTAssertFalse(QuotaCalculator.summarize(accounts: [codex("a", paused: true, weekly: 0, fiveHour: 0)]).hideFromTray)
    }

    func testClaudeStyleSummaryHidesOnlyWithBothKnownTotalsAboveThreshold() {
        func summary(_ accounts: [(Double?, Double?)]) -> ClaudeQuotaSummary {
            ClaudeQuotaCalculator.summarize(accounts: accounts.enumerated().map { index, usage in
                ClaudeAccount(id: "id-\(index)", alias: nil, email: nil, fiveHourUsedPercent: usage.0, weeklyUsedPercent: usage.1)
            })
        }
        XCTAssertTrue(summary([(3, 4.5)]).hideFromTray)
        XCTAssertTrue(summary([(60, 60), (40, 40)]).hideFromTray)
        XCTAssertFalse(summary([(5, 0)]).hideFromTray)
        XCTAssertFalse(summary([(0, 5)]).hideFromTray)
        XCTAssertFalse(summary([(nil, 0)]).hideFromTray)
        XCTAssertFalse(summary([(0, nil)]).hideFromTray)
        XCTAssertFalse(summary([(0, 0), (nil, 0)]).hideFromTray)
        XCTAssertFalse(summary([]).hideFromTray)
    }

    func testLocalDecoderReadsCodexFiveHourFromEitherSpelling() throws {
        let data = Data("""
            {"accounts":[
              {"id":"short","plan":"pro","quota":{"weeklyPercent":1,"shortPercent":2,"shortWindowSeconds":18000}},
              {"id":"five","plan":"pro","quota":{"weeklyPercent":1,"fiveHourPercent":3}},
              {"id":"both","plan":"pro","quota":{"weeklyPercent":1,"fiveHourPercent":4,"shortPercent":9}},
              {"id":"none","plan":"pro","quota":{"weeklyPercent":1}},
              {"id":"missing","plan":"pro","quota":null}
            ]}
            """.utf8)
        let accounts = try OpenCodexResponseDecoder.decodeAccounts(data)
        XCTAssertEqual(accounts.map(\.fiveHourUsedPercent), [2, 3, 4, nil, nil])
        XCTAssertTrue(QuotaCalculator.summarize(accounts: Array(accounts.prefix(3))).hideFromTray)
        XCTAssertFalse(QuotaCalculator.summarize(accounts: accounts).hideFromTray)
    }

    func testHubDecoderReadsOptionalCodexFiveHourUsage() throws {
        let fixture = #"{"schemaVersion":1,"generatedAt":"2026-10-27T12:00:00Z","providers":{"openai":{"enabled":true,"accounts":[{"id":"a","plan":"pro","weeklyPercent":1FIVE_HOUR}]},"anthropic":{"enabled":true,"accounts":[]}}}"#
        let withoutFiveHour = try HubQuotaDecoder.decode(Data(fixture.replacingOccurrences(of: "FIVE_HOUR", with: "").utf8))
        XCTAssertNil(withoutFiveHour.codexSummary?.rows.first?.fiveHourRemainingPercent)
        XCTAssertEqual(withoutFiveHour.codexSummary?.hideFromTray, false)

        let withFiveHour = try HubQuotaDecoder.decode(Data(fixture.replacingOccurrences(of: "FIVE_HOUR", with: ",\"fiveHourPercent\":2").utf8))
        XCTAssertEqual(withFiveHour.codexSummary?.rows.first?.fiveHourRemainingPercent, 98)
        XCTAssertEqual(withFiveHour.codexSummary?.hideFromTray, true)

        XCTAssertThrowsError(try HubQuotaDecoder.decode(Data(fixture.replacingOccurrences(of: "FIVE_HOUR", with: ",\"fiveHourPercent\":101").utf8)))
    }

    func testAllowanceSnapshotsWithoutFiveHourFieldStillDecode() throws {
        let legacy = Data(#"{"accountId":"a","label":"work","remainingPercent":50,"totalPercent":100}"#.utf8)
        let decoded = try JSONDecoder().decode(AccountAllowance.self, from: legacy)
        XCTAssertNil(decoded.fiveHourRemainingPercent)
        XCTAssertFalse(QuotaSummary(trayPercentage: 50, rows: [decoded]).hideFromTray)

        let current = AccountAllowance(accountId: "a", label: "work", remainingPercent: 99, totalPercent: 100, fiveHourRemainingPercent: 97.5)
        let roundTrip = try JSONDecoder().decode(AccountAllowance.self, from: JSONEncoder().encode(current))
        XCTAssertEqual(roundTrip, current)
        XCTAssertTrue(QuotaSummary(trayPercentage: 99, rows: [roundTrip]).hideFromTray)
    }
}
