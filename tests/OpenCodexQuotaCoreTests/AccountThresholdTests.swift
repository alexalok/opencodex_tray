import Foundation
import XCTest
@testable import OpenCodexQuotaCore

final class AccountThresholdTests: XCTestCase {
    func testProLiteOverrideReducesDropdownTotalAndPoolRemaining() throws {
        let accounts = try OpenCodexResponseDecoder.decodeAccounts(Data(#"{"accounts":[{"id":"lite","alias":"Lite","plan":"prolite","autoSwitchThresholdOverride":50,"quota":{"weeklyPercent":20}}]}"#.utf8))
        let summary = QuotaCalculator.summarize(accounts: accounts)
        XCTAssertEqual(summary.rows[0].totalPercent, 12.5)
        XCTAssertEqual(summary.rows[0].remainingPercent, 7.5)
        XCTAssertEqual(summary.trayPercentage, 7)
        XCTAssertEqual(DisplayFormatter.row(summary.rows[0]), "Lite: 7.5%/12.5%")
        XCTAssertEqual(DisplayFormatter.codexAllowance(summary.rows[0]), "7.5% / 12.5%")
    }
    func testThresholdClampsRemainingAndPreservesPausedAndUnknownQuotaRules() throws {
        let accounts = try OpenCodexResponseDecoder.decodeAccounts(Data(#"{"accounts":[{"id":"over","plan":"prolite","autoSwitchThresholdOverride":50,"quota":{"weeklyPercent":60}},{"id":"paused","paused":true,"plan":"pro","autoSwitchThresholdOverride":50,"quota":{"weeklyPercent":10}},{"id":"negative","plan":"prolite","autoSwitchThresholdOverride":50,"quota":{"weeklyPercent":-5}}]}"#.utf8))
        let summary = QuotaCalculator.summarize(accounts: accounts)
        XCTAssertEqual(summary.rows.map(\.remainingPercent), [0, 40, 12.5])
        XCTAssertEqual(summary.trayPercentage, 12)
        let unknown = try OpenCodexResponseDecoder.decodeAccounts(Data(#"{"accounts":[{"id":"unknown","plan":"prolite","autoSwitchThresholdOverride":50}]}"#.utf8))
        let unknownSummary = QuotaCalculator.summarize(accounts: unknown)
        XCTAssertNil(unknownSummary.trayPercentage)
        XCTAssertNil(unknownSummary.rows[0].remainingPercent)
        XCTAssertEqual(unknownSummary.rows[0].totalPercent, 12.5)
    }

    func testInvalidOrAbsentOverridePreservesPublicAllowance() throws {
        for value in ["null", "-1", "101", "50.5", "true", #""50""#, "{}", "[]"] {
            let json = "{\"accounts\":[{\"id\":\"lite\",\"plan\":\"prolite\",\"autoSwitchThresholdOverride\":\(value),\"quota\":{\"weeklyPercent\":20}}]}"
            let accounts = try OpenCodexResponseDecoder.decodeAccounts(Data(json.utf8))
            let summary = QuotaCalculator.summarize(accounts: accounts)
            XCTAssertEqual(summary.rows[0].totalPercent, 25, value)
            XCTAssertEqual(summary.rows[0].remainingPercent, 20, value)
        }
    }

    func testDuplicateMainUsesNamedPoolThreshold() throws {
        let accounts = try OpenCodexResponseDecoder.decodeAccounts(Data(#"{"accounts":[{"id":"__main__","isMain":true,"email":"same@example.com","plan":"prolite","autoSwitchThresholdOverride":80,"quota":{"weeklyPercent":20,"weeklyResetAt":1000}},{"id":"named","alias":"Named","email":"same@example.com","plan":"prolite","autoSwitchThresholdOverride":50,"quota":{"weeklyPercent":20,"weeklyResetAt":1001}}]}"#.utf8))
        let summary = QuotaCalculator.summarize(accounts: accounts)
        XCTAssertEqual(summary.rows.count, 1)
        XCTAssertEqual(summary.rows[0].accountId, "named")
        XCTAssertEqual(summary.rows[0].totalPercent, 12.5)
        XCTAssertEqual(summary.trayPercentage, 7)
    }

}
