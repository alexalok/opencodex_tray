import Foundation
import XCTest
@testable import OpenCodexQuotaCore

final class HubQuotaTests: XCTestCase {
    private let fixture = #"{"schemaVersion":1,"generatedAt":"2026-10-27T12:00:00Z","providers":{"openai":{"enabled":true,"accounts":[{"id":"opaque","alias":"work","plan":"pro","isMain":false,"paused":false,"weeklyPercent":25,"autoSwitchThreshold":90,"resetCreditExpirations":["2026-10-29T12:00:00.000Z"]}]},"anthropic":{"enabled":true,"accounts":[{"id":"claude","fiveHourPercent":null,"weeklyPercent":30}]}}}"#

    func testDecodePreservesThresholdResetDatesAndUnknownQuota() throws {
        let snapshot = try HubQuotaDecoder.decode(Data(fixture.utf8))
        XCTAssertEqual(snapshot.codexSummary?.rows.first?.remainingPercent, 65)
        XCTAssertEqual(snapshot.codexSummary?.rows.first?.resetCreditExpirations?.count, 1)
        XCTAssertNil(snapshot.claudeSummary?.rows.first?.fiveHourRemainingPercent)
        XCTAssertEqual(snapshot.claudeSummary?.rows.first?.weeklyRemainingPercent, 70)
    }
    func testDisabledAndFailedProvidersStayDistinct() throws {
        let data = Data(#"{"schemaVersion":1,"generatedAt":"2026-10-27T12:00:00Z","providers":{"openai":{"enabled":false,"accounts":[]},"anthropic":{"enabled":true,"accounts":[],"error":"upstream secret"}}}"#.utf8)
        let snapshot = try HubQuotaDecoder.decode(data)
        XCTAssertEqual(snapshot.codexEnabled, false)
        XCTAssertEqual(snapshot.codexSummary?.rows, [])
        XCTAssertNil(snapshot.claudeSummary)
        XCTAssertEqual(snapshot.claudeErrorMessage, "Hub Claude quota unavailable")
    }
    func testMalformedAndUnsupportedSnapshotsRejected() {
        for payload in [fixture.replacingOccurrences(of: "\"schemaVersion\":1", with: "\"schemaVersion\":2"),
                        fixture.replacingOccurrences(of: "\"weeklyPercent\":25", with: "\"weeklyPercent\":101"),
                        fixture.replacingOccurrences(of: "2026-10-27T12:00:00Z", with: "bad-date"), "{}"] {
            XCTAssertThrowsError(try HubQuotaDecoder.decode(Data(payload.utf8)))
        }
    }
    func testOldSnapshotStillDecodesWithoutSourceMetadata() throws {
        let old = Data(#"{"fetchedAt":0}"#.utf8)
        let value = try JSONDecoder().decode(QuotaSnapshot.self, from: old)
        XCTAssertNil(value.sourceID)
    }
}
