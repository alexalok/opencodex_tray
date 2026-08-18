import XCTest
@testable import PauseWorkerCore

private actor FakeOpenCodexClient: OpenCodexServing {
    enum FakeError: Error { case claudeUnavailable }

    var accounts: [OpenCodexAccount]
    var claudeAccounts: [ClaudeAccount]
    var pausedIDs: [String] = []
    var fetchDelay: Duration?
    var failClaudeFetch: Bool

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
        if let fetchDelay { try await Task.sleep(for: fetchDelay) }
        return accounts
    }
    func fetchClaudeAccounts() async throws -> [ClaudeAccount] {
        if failClaudeFetch { throw FakeError.claudeUnavailable }
        return claudeAccounts
    }
    func pauseAccount(id: String) async throws { pausedIDs.append(id) }
    func pauses() -> [String] { pausedIDs }
}

final class WorkerTests: XCTestCase {
    func testClaudeFailureDoesNotBlockCodexPause() async throws {
        let client = FakeOpenCodexClient(
            accounts: [
                OpenCodexAccount(id: "friend-id", alias: "workmate", plan: "prolite", isMain: false, paused: false, weeklyUsedPercent: 70),
            ],
            failClaudeFetch: true
        )
        let worker = PauseWorker(client: client, targetAlias: "workmate", thresholdPercent: 70)

        let result = try await worker.refresh()
        let pauses = await client.pauses()

        XCTAssertEqual(result.pausedAccountID, "friend-id")
        XCTAssertEqual(pauses, ["friend-id"])
        XCTAssertNil(result.claudeSummary)
        XCTAssertNotNil(result.claudeErrorMessage)
    }

    func testRefreshReturnsCodexAndRawClaudeFiveHourAndWeeklyPoolSummaries() async throws {
        let client = FakeOpenCodexClient(
            accounts: [
                OpenCodexAccount(id: "friend-id", alias: "workmate", plan: "prolite", isMain: false, paused: false, weeklyUsedPercent: 53),
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
        let worker = PauseWorker(client: client, targetAlias: "workmate", thresholdPercent: 70)

        let result = try await worker.refresh()

        XCTAssertEqual(result.codexSummary.trayPercentage, 4)
        XCTAssertEqual(result.claudeSummary?.fiveHourUsedPercentage, 60)
        XCTAssertEqual(result.claudeSummary?.weeklyUsedPercentage, 80)
        XCTAssertEqual(result.claudeSummary?.rows.map(\.label), ["work", "personal"])
        XCTAssertNil(result.claudeErrorMessage)
    }

    func testRefreshPausesResolvedIDAtThreshold() async throws {
        let client = FakeOpenCodexClient(accounts: [
            OpenCodexAccount(id: "friend-id", alias: "workmate", plan: "prolite", isMain: false, paused: false, weeklyUsedPercent: 70),
        ])
        let worker = PauseWorker(client: client, targetAlias: "workmate", thresholdPercent: 70)

        let result = try await worker.refresh()
        let pauses = await client.pauses()

        XCTAssertEqual(result.pausedAccountID, "friend-id")
        XCTAssertEqual(pauses, ["friend-id"])
    }

    func testRefreshDoesNotRepeatPauseForAlreadyPausedAccount() async throws {
        let client = FakeOpenCodexClient(accounts: [
            OpenCodexAccount(id: "friend-id", alias: "workmate", plan: "prolite", isMain: false, paused: true, weeklyUsedPercent: 90),
        ])
        let worker = PauseWorker(client: client, targetAlias: "workmate", thresholdPercent: 70)

        let result = try await worker.refresh()
        let pauses = await client.pauses()

        XCTAssertNil(result.pausedAccountID)
        XCTAssertEqual(pauses, [])
    }

    func testConcurrentRefreshesCoalesceIntoOnePauseRequest() async throws {
        let client = FakeOpenCodexClient(accounts: [
            OpenCodexAccount(id: "friend-id", alias: "workmate", plan: "prolite", isMain: false, paused: false, weeklyUsedPercent: 70),
        ], fetchDelay: .milliseconds(50))
        let worker = PauseWorker(client: client, targetAlias: "workmate", thresholdPercent: 70)

        async let first = worker.refresh()
        async let second = worker.refresh()
        _ = try await (first, second)

        let pauses = await client.pauses()
        XCTAssertEqual(pauses, ["friend-id"])
    }
}
