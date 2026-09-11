import XCTest
@testable import OpenCodexQuotaCore

final class OpenCodexDecoderTests: XCTestCase {
    func testPreservesAccountPlanForCapacityNormalization() throws {
        let data = Data(#"{"accounts":[{"id":"friend-id","alias":"workmate","plan":"prolite","isMain":false,"quota":{"weeklyPercent":53}}]}"#.utf8)

        let accounts = try OpenCodexResponseDecoder.decodeAccounts(data)

        XCTAssertEqual(accounts, [OpenCodexAccount(
            id: "friend-id",
            alias: "workmate",
            plan: "prolite",
            isMain: false,
            weeklyUsedPercent: 53
        )])
    }

    func testPoolAccountReplacesDuplicateMainInRowsAndTotalRegardlessOfOrder() throws {
        let main = #"{"id":"main","email":"A***9@example.com","plan":" Pro ","isMain":true,"quota":{"weeklyPercent":20,"weeklyResetAt":1789000000}}"#
        let other = #"{"id":"other-id","alias":"imapp2108","email":"i***8@example.com","plan":"pro","isMain":false,"quota":{"weeklyPercent":6,"weeklyResetAt":1789100000}}"#
        let pool = #"{"id":"aleks00799","email":" a***9@example.com ","plan":"pro","isMain":false,"quota":{"weeklyPercent":20,"weeklyResetAt":1789000000}}"#

        for payload in [[main, other, pool], [other, pool, main]] {
            let accounts = try decodeCodexAccounts(payload)
            let summary = QuotaCalculator.summarize(accounts: accounts)

            XCTAssertEqual(accounts.map(\.id), ["other-id", "aleks00799"])
            XCTAssertEqual(summary.rows, [
                AccountAllowance(accountId: "other-id", label: "imapp2108", remainingPercent: 94, totalPercent: 100),
                AccountAllowance(accountId: "aleks00799", label: "aleks00799", remainingPercent: 80, totalPercent: 100),
            ])
            XCTAssertEqual(summary.trayPercentage, 174)
        }
    }

    func testDuplicateMainUsesPoolQuotaEvenWhenUsageSnapshotsDiffer() throws {
        let accounts = try decodeCodexAccounts([
            #"{"id":"main","email":"a***9@example.com","plan":"pro","isMain":true,"quota":{"weeklyPercent":20,"weeklyResetAt":1789000000}}"#,
            #"{"id":"pool-id","alias":"personal","email":"a***9@example.com","plan":"pro","isMain":false,"quota":{"weeklyPercent":23,"weeklyResetAt":1789000000}}"#,
        ])

        let summary = QuotaCalculator.summarize(accounts: accounts)

        XCTAssertEqual(summary.rows, [
            AccountAllowance(accountId: "pool-id", label: "personal", remainingPercent: 77, totalPercent: 100),
        ])
        XCTAssertEqual(summary.trayPercentage, 77)
    }

    func testKeepsMainWhenPoolEmailPlanOrResetDiffers() throws {
        let main = #"{"id":"main","email":"a***9@example.com","plan":"pro","isMain":true,"quota":{"weeklyPercent":20,"weeklyResetAt":1789000000}}"#
        let distinctPoolAccounts = [
            #"{"id":"pool-id","email":"b***9@example.com","plan":"pro","isMain":false,"quota":{"weeklyPercent":20,"weeklyResetAt":1789000000}}"#,
            #"{"id":"pool-id","email":"a***9@example.com","plan":"prolite","isMain":false,"quota":{"weeklyPercent":20,"weeklyResetAt":1789000000}}"#,
            #"{"id":"pool-id","email":"a***9@example.com","plan":"pro","isMain":false,"quota":{"weeklyPercent":20,"weeklyResetAt":1789100000}}"#,
        ]

        for pool in distinctPoolAccounts {
            let accounts = try decodeCodexAccounts([main, pool])

            XCTAssertEqual(accounts.map(\.id), ["main", "pool-id"])
        }
    }

    func testKeepsMainWhenMatchingEvidenceIsMissingOrInvalid() throws {
        let incompleteFields = [
            #""plan":"pro","quota":{"weeklyResetAt":1789000000}"#,
            #""email":" ","plan":"pro","quota":{"weeklyResetAt":1789000000}"#,
            #""email":"Codex App login","plan":"pro","quota":{"weeklyResetAt":1789000000}"#,
            #""email":"a***9@example.com","quota":{"weeklyResetAt":1789000000}"#,
            #""email":"a***9@example.com","plan":" ","quota":{"weeklyResetAt":1789000000}"#,
            #""email":"a***9@example.com","plan":"pro""#,
            #""email":"a***9@example.com","plan":"pro","quota":{"weeklyResetAt":null}"#,
            #""email":"a***9@example.com","plan":"pro","quota":{"weeklyResetAt":0}"#,
            #""email":"a***9@example.com","plan":"pro","quota":{"weeklyResetAt":-1}"#,
        ]

        for fields in incompleteFields {
            let accounts = try decodeCodexAccounts([
                "{\"id\":\"main\",\"isMain\":true,\(fields)}",
                "{\"id\":\"pool-id\",\"isMain\":false,\(fields)}",
            ])

            XCTAssertEqual(accounts.map(\.id), ["main", "pool-id"])
        }
    }

    func testDeduplicationPreservesPoolEntriesAndStandaloneMain() throws {
        let fields = #""email":"a***9@example.com","plan":"pro","quota":{"weeklyPercent":20,"weeklyResetAt":1789000000}"#
        let main = "{\"id\":\"main\",\"isMain\":true,\(fields)}"
        let pool = "{\"id\":\"pool-id\",\(fields)}"
        let anotherPool = "{\"id\":\"another-pool-id\",\"isMain\":false,\(fields)}"

        XCTAssertEqual(try decodeCodexAccounts([main]).map(\.id), ["main"])
        XCTAssertEqual(try decodeCodexAccounts([pool, anotherPool]).map(\.id), ["pool-id", "another-pool-id"])
        XCTAssertEqual(try decodeCodexAccounts([main, pool, anotherPool]).map(\.id), ["pool-id", "another-pool-id"])
    }

    func testDecodesAnthropicAccountAliasesAndFiveHourAndWeeklyUsage() throws {
        let data = Data(#"{"activeAccountId":"claude-a","accounts":[{"id":"claude-a","alias":"work","email":"w***@example.com","active":true,"quota":{"fiveHourPercent":7,"weeklyPercent":35,"updatedAt":1786381200000}},{"id":"claude-b","email":"p***@example.com","active":false,"quotaUnavailable":true}]}"#.utf8)

        let accounts = try OpenCodexResponseDecoder.decodeClaudeAccounts(data)

        XCTAssertEqual(accounts, [
            ClaudeAccount(
                id: "claude-a",
                alias: "work",
                email: "w***@example.com",
                fiveHourUsedPercent: 7,
                weeklyUsedPercent: 35
            ),
            ClaudeAccount(
                id: "claude-b",
                alias: nil,
                email: "p***@example.com",
                fiveHourUsedPercent: nil,
                weeklyUsedPercent: nil
            ),
        ])
    }

    private func decodeCodexAccounts(_ accounts: [String]) throws -> [OpenCodexAccount] {
        try OpenCodexResponseDecoder.decodeAccounts(
            Data("{\"accounts\":[\(accounts.joined(separator: ","))]}".utf8)
        )
    }
}
