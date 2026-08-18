import XCTest
@testable import PauseWorkerCore

final class DisplayFormatterTests: XCTestCase {
    func testFormatsTrayAndAccountRows() {
        XCTAssertEqual(DisplayFormatter.trayTitle(27), "27%")
        XCTAssertEqual(DisplayFormatter.trayTitle(nil), "—")
        XCTAssertEqual(DisplayFormatter.row(AccountAllowance(
            accountId: "friend-id",
            label: "workmate",
            remainingPercent: 4.25,
            totalPercent: 17.5
        )), "workmate: 4.25%/17.5%")
    }

    func testFormatsClaudeFiveHourThenWeeklyUsageForTrayAndDropdown() {
        let summary = ClaudeQuotaSummary(
            fiveHourUsedPercentage: 50,
            weeklyUsedPercentage: 20,
            rows: []
        )
        let row = ClaudeAccountUsage(
            accountId: "claude-a",
            label: "work",
            fiveHourUsedPercent: 50.25,
            weeklyUsedPercent: 20
        )
        let partialRow = ClaudeAccountUsage(
            accountId: "claude-b",
            label: "personal",
            fiveHourUsedPercent: nil,
            weeklyUsedPercent: 20
        )

        XCTAssertEqual(DisplayFormatter.claudeTrayTitle(summary), "50%/20%")
        XCTAssertEqual(DisplayFormatter.claudeRow(row), "work: 50.25%/20%")
        XCTAssertEqual(DisplayFormatter.claudeRow(partialRow), "personal: —/20%")
    }
}
