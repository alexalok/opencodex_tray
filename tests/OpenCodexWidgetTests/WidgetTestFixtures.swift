import Foundation
import PauseWorkerCore

let widgetTestDate = Date(timeIntervalSince1970: 1_788_231_600)

func makeCodexSummary(
    rows: [AccountAllowance] = [
        AccountAllowance(
            accountId: "codex-main",
            label: "main",
            remainingPercent: 68,
            totalPercent: 100
        ),
    ]
) -> QuotaSummary {
    QuotaSummary(trayPercentage: 68, rows: rows)
}

func makeClaudeSummary(
    rows: [ClaudeAccountAllowance] = [
        ClaudeAccountAllowance(
            accountId: "claude-work",
            label: "work",
            fiveHourRemainingPercent: 97,
            weeklyRemainingPercent: 88
        ),
    ]
) -> ClaudeQuotaSummary {
    ClaudeQuotaSummary(
        fiveHourRemainingPercentage: 97,
        weeklyRemainingPercentage: 88,
        rows: rows
    )
}

func makeSnapshot(
    codex: QuotaSummary?,
    codexError: String? = nil,
    claude: ClaudeQuotaSummary?,
    claudeError: String? = nil,
    fetchedAt: Date = widgetTestDate
) -> QuotaSnapshot {
    QuotaSnapshot(
        fetchedAt: fetchedAt,
        codexSummary: codex,
        codexErrorMessage: codexError,
        claudeSummary: claude,
        claudeErrorMessage: claudeError
    )
}

func makeCompleteSnapshot() -> QuotaSnapshot {
    makeSnapshot(codex: makeCodexSummary(), claude: makeClaudeSummary())
}

func makeCompleteLoad() -> QuotaSnapshotLoad {
    QuotaSnapshotLoad(snapshot: makeCompleteSnapshot(), codexAccounts: [])
}

actor FakeSnapshotLoader: QuotaSnapshotLoading {
    let result: QuotaSnapshotLoad

    init(result: QuotaSnapshotLoad) {
        self.result = result
    }

    func load() async -> QuotaSnapshotLoad {
        result
    }
}

actor FakeWidgetCache: WidgetSnapshotCaching {
    private var snapshot: QuotaSnapshot?
    private var savedSnapshots: [QuotaSnapshot] = []

    init(snapshot: QuotaSnapshot? = nil) {
        self.snapshot = snapshot
    }

    func load() async -> QuotaSnapshot? {
        snapshot
    }

    func save(_ snapshot: QuotaSnapshot) async throws {
        self.snapshot = snapshot
        savedSnapshots.append(snapshot)
    }

    func saves() -> [QuotaSnapshot] {
        savedSnapshots
    }
}
