import XCTest
@testable import PauseWorkerCore

final class OpenCodexDecoderTests: XCTestCase {
    func testPreservesAccountPlanForCapacityNormalization() throws {
        let data = Data(#"{"accounts":[{"id":"friend-id","alias":"workmate","plan":"prolite","isMain":false,"paused":false,"quota":{"weeklyPercent":53}}]}"#.utf8)

        let accounts = try OpenCodexResponseDecoder.decodeAccounts(data)

        XCTAssertEqual(accounts, [OpenCodexAccount(
            id: "friend-id",
            alias: "workmate",
            plan: "prolite",
            isMain: false,
            paused: false,
            weeklyUsedPercent: 53
        )])
    }

    func testDecodesAnthropicAccountAliasesAndWeeklyUsage() throws {
        let data = Data(#"{"activeAccountId":"claude-a","accounts":[{"id":"claude-a","alias":"work","email":"w***@example.com","active":true,"quota":{"fiveHourPercent":7,"weeklyPercent":35,"updatedAt":1786381200000}},{"id":"claude-b","email":"p***@example.com","active":false,"quotaUnavailable":true}]}"#.utf8)

        let accounts = try OpenCodexResponseDecoder.decodeClaudeAccounts(data)

        XCTAssertEqual(accounts, [
            ClaudeAccount(id: "claude-a", alias: "work", email: "w***@example.com", weeklyUsedPercent: 35),
            ClaudeAccount(id: "claude-b", alias: nil, email: "p***@example.com", weeklyUsedPercent: nil),
        ])
    }
}
