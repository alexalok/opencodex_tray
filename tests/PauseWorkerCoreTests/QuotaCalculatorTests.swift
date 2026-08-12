import XCTest
@testable import PauseWorkerCore

final class QuotaCalculatorTests: XCTestCase {
    private let accounts = [
        OpenCodexAccount(id: "main-id", alias: nil, plan: "pro", isMain: true, paused: false, weeklyUsedPercent: 100),
        OpenCodexAccount(id: "friend-id", alias: "workmate", plan: "prolite", isMain: false, paused: false, weeklyUsedPercent: 53),
    ]

    func testTrayFloorsSumOfProEquivalentRemainingAllowances() throws {
        let summary = try QuotaCalculator.summarize(
            accounts: accounts,
            targetAlias: "workmate",
            thresholdPercent: 70
        )

        XCTAssertEqual(summary.trayPercentage, 4)
        XCTAssertEqual(summary.rows, [
            AccountAllowance(accountId: "main-id", label: "main", remainingPercent: 0, totalPercent: 100),
            AccountAllowance(accountId: "friend-id", label: "workmate", remainingPercent: 4.25, totalPercent: 17.5),
        ])
    }

    func testTrayTotalCanExceedOneHundredPercent() throws {
        let summary = try QuotaCalculator.summarize(
            accounts: [
                OpenCodexAccount(id: "target-id", alias: "target", plan: "pro", isMain: false, paused: false, weeklyUsedPercent: 0),
                OpenCodexAccount(id: "other-id", alias: "other", plan: "pro", isMain: false, paused: false, weeklyUsedPercent: 0),
            ],
            targetAlias: "target",
            thresholdPercent: 70
        )

        XCTAssertEqual(summary.trayPercentage, 170)
    }

    func testMissingQuotaMakesAggregateUnknownWithoutInventingCapacity() throws {
        let summary = try QuotaCalculator.summarize(
            accounts: [
                OpenCodexAccount(id: "main-id", alias: nil, plan: "pro", isMain: true, paused: false, weeklyUsedPercent: nil),
                accounts[1],
            ],
            targetAlias: "workmate",
            thresholdPercent: 70
        )

        XCTAssertNil(summary.trayPercentage)
        XCTAssertNil(summary.rows[0].remainingPercent)
        XCTAssertEqual(summary.rows[0].totalPercent, 100)
    }

    func testRejectsMissingTargetAlias() {
        XCTAssertThrowsError(try QuotaCalculator.summarize(
            accounts: accounts,
            targetAlias: "missing",
            thresholdPercent: 70
        )) { error in
            XCTAssertEqual(error as? QuotaError, .targetAliasNotFound("missing"))
        }
    }

    func testRejectsDuplicateTargetAlias() {
        XCTAssertThrowsError(try QuotaCalculator.summarize(
            accounts: accounts + [OpenCodexAccount(
                id: "duplicate-id",
                alias: "workmate",
                plan: "prolite",
                isMain: false,
                paused: false,
                weeklyUsedPercent: 10
            )],
            targetAlias: "workmate",
            thresholdPercent: 70
        )) { error in
            XCTAssertEqual(error as? QuotaError, .duplicateTargetAlias("workmate"))
        }
    }

    func testUnknownPlanMakesItsRowAndAggregateUnknown() throws {
        let summary = try QuotaCalculator.summarize(
            accounts: [OpenCodexAccount(
                id: "unknown-id",
                alias: "workmate",
                plan: "future-plan",
                isMain: false,
                paused: false,
                weeklyUsedPercent: 20
            )],
            targetAlias: "workmate",
            thresholdPercent: 70
        )

        XCTAssertNil(summary.trayPercentage)
        XCTAssertNil(summary.rows[0].remainingPercent)
        XCTAssertNil(summary.rows[0].totalPercent)
    }

    func testFloatingPointNoiseDoesNotFloorExactPercentageOnePointLow() throws {
        let summary = try QuotaCalculator.summarize(
            accounts: [
                OpenCodexAccount(id: "main-id", alias: nil, plan: "pro", isMain: true, paused: false, weeklyUsedPercent: 17.525),
                OpenCodexAccount(id: "friend-id", alias: "workmate", plan: "prolite", isMain: false, paused: false, weeklyUsedPercent: 3.9),
            ],
            targetAlias: "workmate",
            thresholdPercent: 70
        )

        XCTAssertEqual(summary.trayPercentage, 99)
    }

    func testClaudeTraySumsRawWeeklyRemainingAllowancesWithoutPlanConversion() {
        let summary = ClaudeQuotaCalculator.summarize(accounts: [
            ClaudeAccount(id: "claude-a", alias: "work", email: "w***@example.com", weeklyUsedPercent: 35),
            ClaudeAccount(id: "claude-b", alias: nil, email: "p***@example.com", weeklyUsedPercent: 60),
        ])

        XCTAssertEqual(summary.trayPercentage, 105)
        XCTAssertEqual(summary.rows, [
            AccountAllowance(accountId: "claude-a", label: "work", remainingPercent: 65, totalPercent: 100),
            AccountAllowance(accountId: "claude-b", label: "p***@example.com", remainingPercent: 40, totalPercent: 100),
        ])
    }
}
