import Foundation
import XCTest
@testable import PauseWorkerCore

private enum FakeQuotaError: LocalizedError, Sendable {
    case codex
    case claude

    var errorDescription: String? {
        switch self {
        case .codex: "Codex unavailable"
        case .claude: "Claude unavailable"
        }
    }
}

private enum FakeOutcome<Value: Sendable>: Sendable {
    case success(Value)
    case failure(FakeQuotaError)
}

private actor ConcurrentFetchProbe {
    private var active = 0
    private var maximum = 0

    func enter() {
        active += 1
        maximum = max(maximum, active)
    }

    func leave() {
        active -= 1
    }

    func maximumActive() -> Int { maximum }
}

private actor FakeQuotaClient: OpenCodexQuotaServing {
    let codexResult: FakeOutcome<[OpenCodexAccount]>
    let claudeResult: FakeOutcome<[ClaudeAccount]>
    let probe: ConcurrentFetchProbe?

    init(
        codexResult: FakeOutcome<[OpenCodexAccount]>,
        claudeResult: FakeOutcome<[ClaudeAccount]>,
        probe: ConcurrentFetchProbe? = nil
    ) {
        self.codexResult = codexResult
        self.claudeResult = claudeResult
        self.probe = probe
    }

    func fetchAccounts() async throws -> [OpenCodexAccount] {
        await probe?.enter()
        if probe != nil { try? await Task.sleep(for: .milliseconds(50)) }
        await probe?.leave()
        switch codexResult {
        case let .success(accounts): return accounts
        case let .failure(error): throw error
        }
    }

    func fetchClaudeAccounts() async throws -> [ClaudeAccount] {
        await probe?.enter()
        if probe != nil { try? await Task.sleep(for: .milliseconds(50)) }
        await probe?.leave()
        switch claudeResult {
        case let .success(accounts): return accounts
        case let .failure(error): throw error
        }
    }
}

private let codexAccounts = [
    OpenCodexAccount(
        id: "friend-id",
        alias: "workmate",
        plan: "prolite",
        isMain: false,
        paused: false,
        weeklyUsedPercent: 53
    ),
]

private let claudeAccounts = [
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

private let quotaSnapshotTestDate = Date(timeIntervalSince1970: 1_788_231_600)

final class QuotaSnapshotLoaderTests: XCTestCase {
    func testCompleteLoadReturnsBothSummariesAndRawCodexAccounts() async {
        let loader = makeLoader(
            codexResult: .success(codexAccounts),
            claudeResult: .success(claudeAccounts)
        )

        let load = await loader.load()

        XCTAssertEqual(load.snapshot.fetchedAt, quotaSnapshotTestDate)
        XCTAssertEqual(load.snapshot.codexSummary?.trayPercentage, 4)
        XCTAssertEqual(load.snapshot.claudeSummary?.fiveHourRemainingPercentage, 140)
        XCTAssertEqual(load.snapshot.claudeSummary?.weeklyRemainingPercentage, 120)
        XCTAssertNil(load.snapshot.codexErrorMessage)
        XCTAssertNil(load.snapshot.claudeErrorMessage)
        XCTAssertEqual(load.codexAccounts, codexAccounts)
    }

    func testClaudeFailureKeepsCodexSnapshot() async {
        let loader = makeLoader(
            codexResult: .success(codexAccounts),
            claudeResult: .failure(.claude)
        )

        let load = await loader.load()

        XCTAssertEqual(load.snapshot.fetchedAt, quotaSnapshotTestDate)
        XCTAssertNotNil(load.snapshot.codexSummary)
        XCTAssertNil(load.snapshot.codexErrorMessage)
        XCTAssertNil(load.snapshot.claudeSummary)
        XCTAssertEqual(load.snapshot.claudeErrorMessage, "Claude unavailable")
        XCTAssertEqual(load.codexAccounts, codexAccounts)
    }

    func testCodexFailureKeepsClaudeSnapshot() async {
        let loader = makeLoader(
            codexResult: .failure(.codex),
            claudeResult: .success(claudeAccounts)
        )

        let load = await loader.load()

        XCTAssertNil(load.snapshot.codexSummary)
        XCTAssertEqual(load.snapshot.codexErrorMessage, "Codex unavailable")
        XCTAssertNotNil(load.snapshot.claudeSummary)
        XCTAssertNil(load.snapshot.claudeErrorMessage)
        XCTAssertNil(load.codexAccounts)
    }

    func testBothFailuresReturnTimestampedEmptySnapshot() async {
        let loader = makeLoader(
            codexResult: .failure(.codex),
            claudeResult: .failure(.claude)
        )

        let load = await loader.load()

        XCTAssertEqual(load.snapshot.fetchedAt, quotaSnapshotTestDate)
        XCTAssertFalse(load.snapshot.hasProviderData)
        XCTAssertEqual(load.snapshot.codexErrorMessage, "Codex unavailable")
        XCTAssertEqual(load.snapshot.claudeErrorMessage, "Claude unavailable")
        XCTAssertNil(load.codexAccounts)
    }

    func testMissingTargetAliasIsCodexOnlyFailure() async {
        let accounts = [
            OpenCodexAccount(
                id: "other-id",
                alias: "other",
                plan: "pro",
                isMain: false,
                paused: false,
                weeklyUsedPercent: 20
            ),
        ]
        let loader = makeLoader(
            codexResult: .success(accounts),
            claudeResult: .success(claudeAccounts)
        )

        let load = await loader.load()

        XCTAssertNil(load.snapshot.codexSummary)
        XCTAssertEqual(
            load.snapshot.codexErrorMessage,
            "Target account alias \"workmate\" was not returned by OpenCodex"
        )
        XCTAssertNotNil(load.snapshot.claudeSummary)
        XCTAssertNil(load.codexAccounts)
    }

    func testDuplicateTargetAliasIsCodexOnlyFailure() async {
        let accounts = [
            OpenCodexAccount(
                id: "first-id",
                alias: "workmate",
                plan: "pro",
                isMain: false,
                paused: false,
                weeklyUsedPercent: 20
            ),
            OpenCodexAccount(
                id: "second-id",
                alias: "workmate",
                plan: "prolite",
                isMain: false,
                paused: false,
                weeklyUsedPercent: 30
            ),
        ]
        let loader = makeLoader(
            codexResult: .success(accounts),
            claudeResult: .success(claudeAccounts)
        )

        let load = await loader.load()

        XCTAssertNil(load.snapshot.codexSummary)
        XCTAssertEqual(
            load.snapshot.codexErrorMessage,
            "Target account alias \"workmate\" matched multiple OpenCodex accounts"
        )
        XCTAssertNotNil(load.snapshot.claudeSummary)
        XCTAssertNil(load.codexAccounts)
    }

    func testRowsPreserveAPIOrder() async {
        let codex = [
            OpenCodexAccount(
                id: "main-id",
                alias: "main",
                plan: "pro",
                isMain: true,
                paused: false,
                weeklyUsedPercent: 20
            ),
            codexAccounts[0],
        ]
        let loader = makeLoader(
            codexResult: .success(codex),
            claudeResult: .success(claudeAccounts)
        )

        let load = await loader.load()

        XCTAssertEqual(load.snapshot.codexSummary?.rows.map(\.label), ["main", "workmate"])
        XCTAssertEqual(load.snapshot.claudeSummary?.rows.map(\.label), ["work", "personal"])
    }

    func testLoadStartsProviderRequestsConcurrently() async {
        let probe = ConcurrentFetchProbe()
        let loader = QuotaSnapshotLoader(
            client: FakeQuotaClient(
                codexResult: .success(codexAccounts),
                claudeResult: .success([]),
                probe: probe
            ),
            targetAlias: "workmate",
            thresholdPercent: 70
        )

        _ = await loader.load()
        let maximumActive = await probe.maximumActive()

        XCTAssertEqual(maximumActive, 2)
    }

    private func makeLoader(
        codexResult: FakeOutcome<[OpenCodexAccount]>,
        claudeResult: FakeOutcome<[ClaudeAccount]>
    ) -> QuotaSnapshotLoader {
        QuotaSnapshotLoader(
            client: FakeQuotaClient(
                codexResult: codexResult,
                claudeResult: claudeResult
            ),
            targetAlias: "workmate",
            thresholdPercent: 70,
            now: { quotaSnapshotTestDate }
        )
    }
}
