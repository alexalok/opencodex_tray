import Foundation
import OpenCodexQuotaCore

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
    QuotaSnapshotLoad(snapshot: makeCompleteSnapshot())
}

func makeThreeAccountSnapshot() -> QuotaSnapshot {
    let codexRows = [
        AccountAllowance(
            accountId: "codex-main",
            label: "main",
            remainingPercent: 68,
            totalPercent: 100
        ),
        AccountAllowance(
            accountId: "codex-work",
            label: "workmate",
            remainingPercent: 16,
            totalPercent: 17.5
        ),
        AccountAllowance(
            accountId: "codex-third",
            label: "third",
            remainingPercent: 10,
            totalPercent: 25
        ),
    ]
    let claudeRows = [
        ClaudeAccountAllowance(
            accountId: "claude-work",
            label: "work",
            fiveHourRemainingPercent: 97,
            weeklyRemainingPercent: 88
        ),
        ClaudeAccountAllowance(
            accountId: "claude-personal",
            label: "personal",
            fiveHourRemainingPercent: 94,
            weeklyRemainingPercent: 88
        ),
        ClaudeAccountAllowance(
            accountId: "claude-third",
            label: "third",
            fiveHourRemainingPercent: 90,
            weeklyRemainingPercent: 80
        ),
    ]
    return makeSnapshot(
        codex: QuotaSummary(trayPercentage: 94, rows: codexRows),
        claude: ClaudeQuotaSummary(
            fiveHourRemainingPercentage: 281,
            weeklyRemainingPercentage: 256,
            rows: claudeRows
        )
    )
}

func makeCodexOnlySnapshot() -> QuotaSnapshot {
    makeSnapshot(
        codex: makeCodexSummary(),
        claude: nil,
        claudeError: "Claude unavailable"
    )
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
