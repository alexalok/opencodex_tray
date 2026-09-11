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
        let main = #"{"id":"main","email":"P***L@example.com","plan":" Pro ","isMain":true,"quota":{"weeklyPercent":20,"weeklyResetAt":1789000000}}"#
        let other = #"{"id":"other-id","alias":"teammate","email":"t***e@example.com","plan":"pro","isMain":false,"quota":{"weeklyPercent":6,"weeklyResetAt":1789100000}}"#
        let pool = #"{"id":"personal-pool","email":" p***l@example.com ","plan":"pro","isMain":false,"quota":{"weeklyPercent":20,"weeklyResetAt":1789000000}}"#

        for payload in [[main, other, pool], [other, pool, main]] {
            let accounts = try decodeCodexAccounts(payload)
            let summary = QuotaCalculator.summarize(accounts: accounts)

            XCTAssertEqual(accounts.map(\.id), ["other-id", "personal-pool"])
            XCTAssertEqual(summary.rows, [
                AccountAllowance(accountId: "other-id", label: "teammate", remainingPercent: 94, totalPercent: 100),
                AccountAllowance(accountId: "personal-pool", label: "personal-pool", remainingPercent: 80, totalPercent: 100),
            ])
            XCTAssertEqual(summary.trayPercentage, 174)
        }
    }

    func testDuplicateMainUsesPoolQuotaEvenWhenUsageSnapshotsDiffer() throws {
        let accounts = try decodeCodexAccounts([
            #"{"id":"main","email":"p***l@example.com","plan":"pro","isMain":true,"quota":{"weeklyPercent":20,"weeklyResetAt":1789000000}}"#,
            #"{"id":"pool-id","alias":"personal","email":"p***l@example.com","plan":"pro","isMain":false,"quota":{"weeklyPercent":23,"weeklyResetAt":1789000000}}"#,
        ])

        let summary = QuotaCalculator.summarize(accounts: accounts)

        XCTAssertEqual(summary.rows, [
            AccountAllowance(accountId: "pool-id", label: "personal", remainingPercent: 77, totalPercent: 100),
        ])
        XCTAssertEqual(summary.trayPercentage, 77)
    }

    func testDuplicateMainIgnoresResetTimestampJitter() throws {
        let poolReset = 1_700_000_099.0
        // Header and usage-API snapshots of the same account can disagree by a second.
        // Include both directions and cross-second boundaries without rounding buckets.
        for drift in [0.0, 1.0, -1.0, 2.0, -2.0, 0.5, -0.5] {
            let main = """
                {"id":"__main__","email":"p***l@example.com","plan":"pro","isMain":true,"quota":{"weeklyPercent":55,"weeklyResetAt":\(poolReset + drift)}}
                """
            let other = #"{"id":"other-id","alias":"teammate","email":"t***e@example.com","plan":"pro","isMain":false,"quota":{"weeklyPercent":10,"weeklyResetAt":1700100000}}"#
            let pool = """
                {"id":"personal-pool","email":"p***l@example.com","plan":"pro","isMain":false,"quota":{"weeklyPercent":55,"weeklyResetAt":\(poolReset)}}
                """

            for payload in [[main, other, pool], [other, pool, main]] {
                let accounts = try decodeCodexAccounts(payload)
                let summary = QuotaCalculator.summarize(accounts: accounts)

                XCTAssertEqual(accounts.map(\.id), ["other-id", "personal-pool"], "drift: \(drift)")
                XCTAssertEqual(summary.trayPercentage, 135, "drift: \(drift)")
            }
        }
    }

    func testKeepsMainWhenResetDifferenceExceedsJitterTolerance() throws {
        let poolReset = 1_700_000_099.0
        for drift in [2.001, -2.001, 60, -60, 604_800] {
            let accounts = try decodeCodexAccounts([
                """
                {"id":"__main__","email":"p***l@example.com","plan":"pro","isMain":true,"quota":{"weeklyPercent":55,"weeklyResetAt":\(poolReset + drift)}}
                """,
                """
                {"id":"pool-id","email":"p***l@example.com","plan":"pro","isMain":false,"quota":{"weeklyPercent":55,"weeklyResetAt":\(poolReset)}}
                """,
            ])

            XCTAssertEqual(accounts.map(\.id), ["__main__", "pool-id"], "drift: \(drift)")
        }
    }

    func testKeepsMainWhenPoolEmailPlanOrResetDiffers() throws {
        let main = #"{"id":"main","email":"p***l@example.com","plan":"pro","isMain":true,"quota":{"weeklyPercent":20,"weeklyResetAt":1789000000}}"#
        let distinctPoolAccounts = [
            #"{"id":"pool-id","email":"b***9@example.com","plan":"pro","isMain":false,"quota":{"weeklyPercent":20,"weeklyResetAt":1789000000}}"#,
            #"{"id":"pool-id","email":"p***l@example.com","plan":"prolite","isMain":false,"quota":{"weeklyPercent":20,"weeklyResetAt":1789000000}}"#,
            #"{"id":"pool-id","email":"p***l@example.com","plan":"pro","isMain":false,"quota":{"weeklyPercent":20,"weeklyResetAt":1789100000}}"#,
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
            #""email":"p***l@example.com","quota":{"weeklyResetAt":1789000000}"#,
            #""email":"p***l@example.com","plan":" ","quota":{"weeklyResetAt":1789000000}"#,
            #""email":"p***l@example.com","plan":"pro""#,
            #""email":"p***l@example.com","plan":"pro","quota":{"weeklyResetAt":null}"#,
            #""email":"p***l@example.com","plan":"pro","quota":{"weeklyResetAt":0}"#,
            #""email":"p***l@example.com","plan":"pro","quota":{"weeklyResetAt":-1}"#,
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
        let fields = #""email":"p***l@example.com","plan":"pro","quota":{"weeklyPercent":20,"weeklyResetAt":1789000000}"#
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
