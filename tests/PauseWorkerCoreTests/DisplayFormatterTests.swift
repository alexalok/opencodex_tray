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

    func testFormatsClaudeFiveHourThenWeeklyRemainingForTrayAndDropdown() {
        let summary = ClaudeQuotaSummary(
            fiveHourRemainingPercentage: 50,
            weeklyRemainingPercentage: 20,
            rows: []
        )
        let row = ClaudeAccountAllowance(
            accountId: "claude-a",
            label: "work",
            fiveHourRemainingPercent: 50.25,
            weeklyRemainingPercent: 20
        )
        let partialRow = ClaudeAccountAllowance(
            accountId: "claude-b",
            label: "personal",
            fiveHourRemainingPercent: nil,
            weeklyRemainingPercent: 20
        )

        XCTAssertEqual(DisplayFormatter.claudeTrayTitle(summary), "50%/20%")
        XCTAssertEqual(DisplayFormatter.claudeRow(row), "work: 50.25%/20%")
        XCTAssertEqual(DisplayFormatter.claudeRow(partialRow), "personal: —/20%")
    }
}
