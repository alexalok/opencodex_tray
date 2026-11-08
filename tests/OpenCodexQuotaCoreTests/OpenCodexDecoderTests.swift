import XCTest
@testable import OpenCodexQuotaCore

final class OpenCodexDecoderTests: XCTestCase {
    func testSkipsMainWithoutCredentialAndKeepsPoolTotalAvailable() throws {
        let accounts = try decodeCodexAccounts([
            #"{"id":"__main__","isMain":true,"email":"Codex App login","hasCredential":false,"needsReauth":false,"quota":null}"#,
            #"{"id":"pool","isMain":false,"hasCredential":true,"plan":"prolite","quota":{"weeklyPercent":7.5}}"#,
        ])

        XCTAssertEqual(accounts.map(\.id), ["pool"])
        let summary = QuotaCalculator.summarize(accounts: accounts)
        XCTAssertEqual(summary.rows.count, 1)
        XCTAssertEqual(summary.trayPercentage, 23) // floor(25 * 0.925)
    }

    func testSkipsEmptyMainWithExplicitMissingCredentialReason() throws {
        let accounts = try decodeCodexAccounts([
            #"{"id":"__main__","isMain":true,"email":"Codex App login","hasCredential":false,"needsReauth":true,"reauthReason":"missing_credential","quota":null}"#,
        ])
        XCTAssertTrue(accounts.isEmpty)
    }

    func testKeepsMainWithCredentialWhenUsageFails() throws {
        for reason in ["unauthorized", "refresh_failed"] {
            let accounts = try decodeCodexAccounts([
                """
                {"id":"__main__","isMain":true,"hasCredential":true,"needsReauth":true,"reauthReason":"\(reason)","quotaRefresh":{"status":"http_error"},"quota":null}
                """,
            ])
            XCTAssertEqual(accounts.map(\.id), ["__main__"])
            XCTAssertNil(QuotaCalculator.summarize(accounts: accounts).trayPercentage)
        }
    }

    func testKeepsMainWhenCredentialPresenceIsUnknown() throws {
        for field in ["", ",\"hasCredential\":null"] {
            let accounts = try decodeCodexAccounts([
                "{\"id\":\"__main__\",\"isMain\":true,\"quota\":null\(field)}",
            ])
            XCTAssertEqual(accounts.map(\.id), ["__main__"])
        }
    }

    func testKeepsMainWithCredentialReadFailureAndKnownAccountOrError() throws {
        for evidence in [
            #""email":"m***n@example.com""#,
            #""plan":"pro""#,
            #""quota":{"weeklyPercent":20}"#,
            #""quotaRefresh":{"status":"http_error"}"#,
            #""reauthReason":"refresh_failed""#,
            #""needsReauth":true"#,
        ] {
            let accounts = try decodeCodexAccounts([
                "{\"id\":\"__main__\",\"isMain\":true,\"hasCredential\":false,\(evidence)}",
            ])
            XCTAssertEqual(accounts.map(\.id), ["__main__"], evidence)
        }
    }

    func testKeepsPoolAccountWithoutCredential() throws {
        let accounts = try decodeCodexAccounts([
            #"{"id":"pool","isMain":false,"hasCredential":false,"needsReauth":true,"quota":null}"#,
        ])
        XCTAssertEqual(accounts.map(\.id), ["pool"])
    }

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

    func testPlusAccountWithFiveHourWindowKeepsKnownWeeklyAllowance() throws {
        // Short-window utilization must not replace the independent weekly reading,
        // even when the five-hour window is exhausted.
        for shortPercent in [0, 67, 100] {
            let accounts = try decodeCodexAccounts([
                #"{"id":"pro-id","alias":"Pro","plan":"pro","quota":{"weeklyPercent":26}}"#,
                """
                {"id":"plus-id","alias":"Plus","plan":"plus","autoSwitchThresholdOverride":99,"quota":{"weeklyPercent":28,"weeklyResetAt":1792306760,"shortPercent":\(shortPercent),"shortResetAt":1791804021,"shortWindowSeconds":18000}}
                """,
            ])
            let summary = QuotaCalculator.summarize(accounts: accounts)

            XCTAssertEqual(accounts[1].weeklyUsedPercent, 28)
            XCTAssertEqual(summary.rows[1].remainingPercent ?? -1, 3.55, accuracy: 1e-9)
            XCTAssertEqual(summary.rows[1].totalPercent, 4.95)
            XCTAssertEqual(DisplayFormatter.row(summary.rows[1]), "Plus: 3.55%/4.95%")
            XCTAssertEqual(DisplayFormatter.codexAllowance(summary.rows[1]), "3.55% / 4.95%")
            XCTAssertEqual(summary.trayPercentage, 77)
        }
    }

    func testPlusPlanNormalizationWithoutThresholdUsesFullWeeklyAllowance() throws {
        let accounts = try decodeCodexAccounts([
            #"{"id":"plus-id","alias":"Plus","plan":" Plus ","quota":{"weeklyPercent":28,"shortPercent":67,"shortWindowSeconds":18000}}"#,
        ])
        let summary = QuotaCalculator.summarize(accounts: accounts)

        XCTAssertEqual(summary.rows[0].remainingPercent, 3.6)
        XCTAssertEqual(summary.rows[0].totalPercent, 5)
        XCTAssertEqual(summary.trayPercentage, 3)
    }

    func testPlusShortWindowDoesNotInventMissingWeeklyAllowance() throws {
        let accounts = try decodeCodexAccounts([
            #"{"id":"plus-id","alias":"Plus","plan":"plus","quota":{"shortPercent":67,"shortWindowSeconds":18000}}"#,
        ])
        let summary = QuotaCalculator.summarize(accounts: accounts)

        XCTAssertNil(summary.rows[0].remainingPercent)
        XCTAssertEqual(summary.rows[0].totalPercent, 5)
        XCTAssertNil(summary.trayPercentage)
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

    func testPausedAccountsRemainVisibleButDoNotContributeToTrayTotal() throws {
        let accounts = try decodeCodexAccounts([
            #"{"id":"active","alias":"work","plan":"pro","paused":false,"quota":{"weeklyPercent":20}}"#,
            #"{"id":"paused","alias":"personal","plan":"prolite","paused":true,"quota":{"weeklyPercent":12}}"#,
        ])
        let summary = QuotaCalculator.summarize(accounts: accounts)

        XCTAssertEqual(summary.trayPercentage, 80)
        XCTAssertEqual(summary.rows.count, 2)
        XCTAssertEqual(summary.rows[1].remainingPercent, 22)
        XCTAssertEqual(DisplayFormatter.row(summary.rows[1]), "personal: 22%/25% (paused)")
        XCTAssertEqual(DisplayFormatter.row(summary.rows[0]), "work: 80%/100%")
        let restored = try JSONDecoder().decode(QuotaSummary.self, from: JSONEncoder().encode(summary))
        XCTAssertEqual(DisplayFormatter.row(restored.rows[1]), "personal: 22%/25% (paused)")
    }

    func testPausedUnknownQuotaOrPlanDoesNotMakeActiveTotalUnknown() throws {
        let accounts = try decodeCodexAccounts([
            #"{"id":"active","plan":"pro","quota":{"weeklyPercent":20}}"#,
            #"{"id":"paused-missing","plan":"pro","paused":true}"#,
            #"{"id":"paused-unknown","plan":"future","paused":true,"quota":{"weeklyPercent":10}}"#,
        ])
        let summary = QuotaCalculator.summarize(accounts: accounts)

        XCTAssertEqual(summary.trayPercentage, 80)
        XCTAssertEqual(summary.rows.count, 3)
        XCTAssertNil(summary.rows[1].remainingPercent)
        XCTAssertNil(summary.rows[2].totalPercent)
        XCTAssertEqual(QuotaCalculator.summarize(accounts: Array(accounts.dropFirst())).trayPercentage, 0)
    }

    func testPoolAccountReplacesDuplicateMainRegardlessOfPauseStateOrOrder() throws {
        for mainPaused in [true, false] {
            for poolPaused in [true, false] {
                let fields = #""email":"p***l@example.com","plan":"pro","quota":{"weeklyPercent":14,"weeklyResetAt":1789000000}"#
                let main = "{\"id\":\"main\",\"isMain\":true,\"paused\":\(mainPaused),\(fields)}"
                let pool = "{\"id\":\"pool\",\"alias\":\"personal\",\"paused\":\(poolPaused),\(fields)}"
                for payload in [[main, pool], [pool, main]] {
                    let accounts = try decodeCodexAccounts(payload)
                    let summary = QuotaCalculator.summarize(accounts: accounts)

                    XCTAssertEqual(accounts.map(\.id), ["pool"])
                    XCTAssertEqual(summary.rows.count, 1)
                    XCTAssertEqual(summary.rows.first?.paused, poolPaused)
                    XCTAssertEqual(summary.trayPercentage, poolPaused ? 0 : 86)
                    XCTAssertEqual(
                        summary.rows.first.map(DisplayFormatter.row),
                        poolPaused ? "personal: 86%/100% (paused)" : "personal: 86%/100%"
                    )
                }
            }
        }
    }

    func testLegacyCachedRowsStillDecodeAsUnpaused() throws {
        let data = Data(#"{"trayPercentage":80,"rows":[{"accountId":"old","label":"old","remainingPercent":80,"totalPercent":100}]}"#.utf8)
        let summary = try JSONDecoder().decode(QuotaSummary.self, from: data)

        XCTAssertEqual(DisplayFormatter.row(summary.rows[0]), "old: 80%/100%")
    }

    private func decodeCodexAccounts(_ accounts: [String]) throws -> [OpenCodexAccount] {
        try OpenCodexResponseDecoder.decodeAccounts(
            Data("{\"accounts\":[\(accounts.joined(separator: ","))]}".utf8)
        )
    }
}
