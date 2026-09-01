import Foundation
import XCTest
@testable import PauseWorkerCore

private actor FakeSnapshotLoader: QuotaSnapshotLoading {
    let result: QuotaSnapshotLoad
    let delay: Duration?
    private var callCount = 0

    init(result: QuotaSnapshotLoad, delay: Duration? = nil) {
        self.result = result
        self.delay = delay
    }

    func load() async -> QuotaSnapshotLoad {
        callCount += 1
        if let delay { try? await Task.sleep(for: delay) }
        return result
    }

    func calls() -> Int { callCount }
}

private enum FakePauseError: LocalizedError, Sendable {
    case unavailable

    var errorDescription: String? { "Pause unavailable" }
}

private actor FakePauser: OpenCodexPausing {
    let error: FakePauseError?
    private var pausedIDs: [String] = []

    init(error: FakePauseError? = nil) {
        self.error = error
    }

    func pauseAccount(id: String) async throws {
        if let error { throw error }
        pausedIDs.append(id)
    }

    func pauses() -> [String] { pausedIDs }
}

private let workerTestDate = Date(timeIntervalSince1970: 1_788_231_600)

private func makeCodexSummary() -> QuotaSummary {
    QuotaSummary(
        trayPercentage: 0,
        rows: [
            AccountAllowance(
                accountId: "friend-id",
                label: "workmate",
                remainingPercent: 0,
                totalPercent: 17.5
            ),
        ]
    )
}

private func makeClaudeSummary() -> ClaudeQuotaSummary {
    ClaudeQuotaSummary(
        fiveHourRemainingPercentage: 97,
        weeklyRemainingPercentage: 88,
        rows: []
    )
}

private func makeSnapshot(
    codexSummary: QuotaSummary? = makeCodexSummary(),
    codexErrorMessage: String? = nil,
    claudeSummary: ClaudeQuotaSummary? = makeClaudeSummary(),
    claudeErrorMessage: String? = nil
) -> QuotaSnapshot {
    QuotaSnapshot(
        fetchedAt: workerTestDate,
        codexSummary: codexSummary,
        codexErrorMessage: codexErrorMessage,
        claudeSummary: claudeSummary,
        claudeErrorMessage: claudeErrorMessage
    )
}

private func makeTargetAccount(
    paused: Bool = false,
    weeklyUsedPercent: Double? = 70
) -> OpenCodexAccount {
    OpenCodexAccount(
        id: "friend-id",
        alias: "workmate",
        plan: "prolite",
        isMain: false,
        paused: paused,
        weeklyUsedPercent: weeklyUsedPercent
    )
}

final class WorkerTests: XCTestCase {
    func testRefreshPausesResolvedIDAtThreshold() async throws {
        let snapshot = makeSnapshot()
        let loader = FakeSnapshotLoader(
            result: QuotaSnapshotLoad(
                snapshot: snapshot,
                codexAccounts: [makeTargetAccount()]
            )
        )
        let pauser = FakePauser()
        let worker = makeWorker(loader: loader, pauser: pauser)

        let result = try await worker.refresh()
        let pauses = await pauser.pauses()

        XCTAssertEqual(result.snapshot, snapshot)
        XCTAssertEqual(result.pausedAccountID, "friend-id")
        XCTAssertEqual(pauses, ["friend-id"])
    }

    func testClaudeFailureDoesNotBlockCodexPause() async throws {
        let snapshot = makeSnapshot(
            claudeSummary: nil,
            claudeErrorMessage: "Claude unavailable"
        )
        let loader = FakeSnapshotLoader(
            result: QuotaSnapshotLoad(
                snapshot: snapshot,
                codexAccounts: [makeTargetAccount()]
            )
        )
        let pauser = FakePauser()
        let worker = makeWorker(loader: loader, pauser: pauser)

        let result = try await worker.refresh()
        let pauses = await pauser.pauses()

        XCTAssertEqual(result.snapshot, snapshot)
        XCTAssertEqual(result.pausedAccountID, "friend-id")
        XCTAssertEqual(pauses, ["friend-id"])
    }

    func testCodexFailureReturnsClaudeAndDoesNotPause() async throws {
        let snapshot = makeSnapshot(
            codexSummary: nil,
            codexErrorMessage: "Codex unavailable"
        )
        let loader = FakeSnapshotLoader(
            result: QuotaSnapshotLoad(snapshot: snapshot, codexAccounts: nil)
        )
        let pauser = FakePauser()
        let worker = makeWorker(loader: loader, pauser: pauser)

        let result = try await worker.refresh()
        let pauses = await pauser.pauses()

        XCTAssertEqual(result.snapshot, snapshot)
        XCTAssertNil(result.pausedAccountID)
        XCTAssertEqual(pauses, [])
    }

    func testRefreshDoesNotRepeatPauseForAlreadyPausedAccount() async throws {
        let loader = FakeSnapshotLoader(
            result: QuotaSnapshotLoad(
                snapshot: makeSnapshot(),
                codexAccounts: [makeTargetAccount(paused: true, weeklyUsedPercent: 90)]
            )
        )
        let pauser = FakePauser()
        let worker = makeWorker(loader: loader, pauser: pauser)

        let result = try await worker.refresh()
        let pauses = await pauser.pauses()

        XCTAssertNil(result.pausedAccountID)
        XCTAssertEqual(pauses, [])
    }

    func testRefreshDoesNotPauseBelowThreshold() async throws {
        let loader = FakeSnapshotLoader(
            result: QuotaSnapshotLoad(
                snapshot: makeSnapshot(),
                codexAccounts: [makeTargetAccount(weeklyUsedPercent: 69.9)]
            )
        )
        let pauser = FakePauser()
        let worker = makeWorker(loader: loader, pauser: pauser)

        let result = try await worker.refresh()
        let pauses = await pauser.pauses()

        XCTAssertNil(result.pausedAccountID)
        XCTAssertEqual(pauses, [])
    }

    func testPauseFailurePropagates() async {
        let loader = FakeSnapshotLoader(
            result: QuotaSnapshotLoad(
                snapshot: makeSnapshot(),
                codexAccounts: [makeTargetAccount()]
            )
        )
        let worker = makeWorker(loader: loader, pauser: FakePauser(error: .unavailable))

        do {
            _ = try await worker.refresh()
            XCTFail("Expected pause error")
        } catch {
            XCTAssertEqual(error.localizedDescription, "Pause unavailable")
        }
    }

    func testConcurrentRefreshesCoalesceLoaderAndPause() async throws {
        let snapshot = makeSnapshot()
        let loader = FakeSnapshotLoader(
            result: QuotaSnapshotLoad(
                snapshot: snapshot,
                codexAccounts: [makeTargetAccount()]
            ),
            delay: .milliseconds(50)
        )
        let pauser = FakePauser()
        let worker = makeWorker(loader: loader, pauser: pauser)

        async let first = worker.refresh()
        async let second = worker.refresh()
        let results = try await [first, second]

        let calls = await loader.calls()
        let pauses = await pauser.pauses()
        XCTAssertEqual(results, [
            WorkerRefresh(snapshot: snapshot, pausedAccountID: "friend-id"),
            WorkerRefresh(snapshot: snapshot, pausedAccountID: "friend-id"),
        ])
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(pauses, ["friend-id"])
    }

    private func makeWorker(
        loader: FakeSnapshotLoader,
        pauser: FakePauser
    ) -> PauseWorker {
        PauseWorker(
            loader: loader,
            pauser: pauser,
            targetAlias: "workmate",
            thresholdPercent: 70
        )
    }
}
