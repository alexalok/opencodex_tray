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
}
