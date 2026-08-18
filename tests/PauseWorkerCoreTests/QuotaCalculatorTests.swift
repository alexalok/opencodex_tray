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

    func testClaudeSummaryConvertsUsedPercentagesToRemainingAllowances() {
        let summary = ClaudeQuotaCalculator.summarize(accounts: [
            ClaudeAccount(
                id: "claude-a",
                alias: "work",
                email: "w***@example.com",
                fiveHourUsedPercent: 3,
                weeklyUsedPercent: 12
            ),
        ])

        XCTAssertEqual(summary.fiveHourRemainingPercentage, 97)
        XCTAssertEqual(summary.weeklyRemainingPercentage, 88)
        XCTAssertEqual(summary.rows, [
            ClaudeAccountAllowance(
                accountId: "claude-a",
                label: "work",
                fiveHourRemainingPercent: 97,
                weeklyRemainingPercent: 88
            ),
        ])
    }

    func testClaudeSummarySumsFiveHourAndWeeklyRemainingAllowancesInDisplayOrder() {
        let summary = ClaudeQuotaCalculator.summarize(accounts: [
            ClaudeAccount(
                id: "claude-a",
                alias: "work",
                email: "w***@example.com",
                fiveHourUsedPercent: 50,
                weeklyUsedPercent: 20
            ),
            ClaudeAccount(
                id: "claude-b",
                alias: nil,
                email: "p***@example.com",
                fiveHourUsedPercent: 10,
                weeklyUsedPercent: 60
            ),
        ])

        XCTAssertEqual(summary.fiveHourRemainingPercentage, 140)
        XCTAssertEqual(summary.weeklyRemainingPercentage, 120)
        XCTAssertEqual(summary.rows, [
            ClaudeAccountAllowance(
                accountId: "claude-a",
                label: "work",
                fiveHourRemainingPercent: 50,
                weeklyRemainingPercent: 80
            ),
            ClaudeAccountAllowance(
                accountId: "claude-b",
                label: "p***@example.com",
                fiveHourRemainingPercent: 90,
                weeklyRemainingPercent: 40
            ),
        ])
    }

    func testClaudeSummaryMarksOnlyMissingAggregateWindowUnknown() {
        let summary = ClaudeQuotaCalculator.summarize(accounts: [
            ClaudeAccount(
                id: "claude-a",
                alias: "work",
                email: nil,
                fiveHourUsedPercent: nil,
                weeklyUsedPercent: 20
            ),
            ClaudeAccount(
                id: "claude-b",
                alias: "personal",
                email: nil,
                fiveHourUsedPercent: 10,
                weeklyUsedPercent: 30
            ),
        ])

        XCTAssertNil(summary.fiveHourRemainingPercentage)
        XCTAssertEqual(summary.weeklyRemainingPercentage, 150)
    }
}
