import XCTest
@testable import OpenCodexQuotaCore

private actor FakeOpenCodexClient: OpenCodexQuotaServing {
    enum FakeError: Error { case claudeUnavailable }

    var accounts: [OpenCodexAccount]
    var claudeAccounts: [ClaudeAccount]
    var fetchDelay: Duration?
    var failClaudeFetch: Bool
    private var accountFetchCount = 0

    init(
        accounts: [OpenCodexAccount],
        claudeAccounts: [ClaudeAccount] = [],
        fetchDelay: Duration? = nil,
        failClaudeFetch: Bool = false
    ) {
        self.accounts = accounts
        self.claudeAccounts = claudeAccounts
        self.fetchDelay = fetchDelay
        self.failClaudeFetch = failClaudeFetch
    }
    func fetchAccounts() async throws -> [OpenCodexAccount] {
        accountFetchCount += 1
        if let fetchDelay { try await Task.sleep(for: fetchDelay) }
        return accounts
    }
    func fetchClaudeAccounts() async throws -> [ClaudeAccount] {
        if failClaudeFetch { throw FakeError.claudeUnavailable }
        return claudeAccounts
    }
    func fetchCount() -> Int { accountFetchCount }
}

final class QuotaRefresherTests: XCTestCase {
    func testClaudeFailureDoesNotBlockCodexRefresh() async throws {
        let client = FakeOpenCodexClient(
            accounts: [
                OpenCodexAccount(id: "friend-id", alias: "workmate", plan: "prolite", isMain: false, weeklyUsedPercent: 70),
            ],
            failClaudeFetch: true
        )
        let refresher = QuotaRefresher(client: client)

        let result = try await refresher.refresh()

        XCTAssertEqual(result.codexSummary.trayPercentage, 7)
        XCTAssertNil(result.claudeSummary)
        XCTAssertNotNil(result.claudeErrorMessage)
    }

    func testRefreshReturnsCodexAndClaudeRemainingPoolSummaries() async throws {
        let client = FakeOpenCodexClient(
            accounts: [
                OpenCodexAccount(id: "friend-id", alias: "workmate", plan: "prolite", isMain: false, weeklyUsedPercent: 53),
            ],
            claudeAccounts: [
                ClaudeAccount(
                    id: "claude-a",
                    alias: "work",
                    email: "w***@example.com",
                    fiveHourUsedPercent: 50,
                    weeklyUsedPercent: 20
                ),
                ClaudeAccount(
                    id: "claude-b",
                    alias: "personal",
                    email: "p***@example.com",
                    fiveHourUsedPercent: 10,
                    weeklyUsedPercent: 60
                ),
            ]
        )
        let refresher = QuotaRefresher(client: client)

        let result = try await refresher.refresh()

        XCTAssertEqual(result.codexSummary.trayPercentage, 11)
        XCTAssertEqual(result.claudeSummary?.fiveHourRemainingPercentage, 140)
        XCTAssertEqual(result.claudeSummary?.weeklyRemainingPercentage, 120)
        XCTAssertEqual(result.claudeSummary?.rows.map(\.label), ["work", "personal"])
        XCTAssertNil(result.claudeErrorMessage)
    }

    func testRefreshUsesFullAllowanceForEveryAccount() async throws {
        let client = FakeOpenCodexClient(accounts: [
            OpenCodexAccount(id: "friend-id", alias: "workmate", plan: "prolite", isMain: false, weeklyUsedPercent: 70),
        ])
        let refresher = QuotaRefresher(client: client)

        let result = try await refresher.refresh()

        XCTAssertEqual(result.codexSummary.rows, [
            AccountAllowance(
                accountId: "friend-id",
                label: "workmate",
                remainingPercent: 7.5,
                totalPercent: 25
            ),
        ])
    }

    func testConcurrentRefreshesCoalesceIntoOneAccountRequest() async throws {
        let client = FakeOpenCodexClient(accounts: [
            OpenCodexAccount(id: "friend-id", alias: "workmate", plan: "prolite", isMain: false, weeklyUsedPercent: 70),
        ], fetchDelay: .milliseconds(50))
        let refresher = QuotaRefresher(client: client)

        async let first = refresher.refresh()
        async let second = refresher.refresh()
        _ = try await (first, second)

        let fetchCount = await client.fetchCount()
        XCTAssertEqual(fetchCount, 1)
    }
}
