import Foundation

public struct QuotaSnapshot: Codable, Equatable, Sendable {
    public let fetchedAt: Date
    public let codexSummary: QuotaSummary?
    public let codexErrorMessage: String?
    public let claudeSummary: ClaudeQuotaSummary?
    public let claudeErrorMessage: String?

    public init(
        fetchedAt: Date,
        codexSummary: QuotaSummary?,
        codexErrorMessage: String?,
        claudeSummary: ClaudeQuotaSummary?,
        claudeErrorMessage: String?
    ) {
        self.fetchedAt = fetchedAt
        self.codexSummary = codexSummary
        self.codexErrorMessage = codexErrorMessage
        self.claudeSummary = claudeSummary
        self.claudeErrorMessage = claudeErrorMessage
    }

    public var isComplete: Bool {
        codexSummary != nil && claudeSummary != nil
    }

    public var hasProviderData: Bool {
        codexSummary != nil || claudeSummary != nil
    }
}

public struct QuotaSnapshotLoad: Equatable, Sendable {
    public let snapshot: QuotaSnapshot

    public init(snapshot: QuotaSnapshot) {
        self.snapshot = snapshot
    }
}

public protocol QuotaSnapshotLoading: Sendable {
    func load() async -> QuotaSnapshotLoad
}

public struct QuotaSnapshotLoader: QuotaSnapshotLoading {
    private let client: any OpenCodexQuotaServing
    private let now: @Sendable () -> Date

    public init(
        client: any OpenCodexQuotaServing,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.client = client
        self.now = now
    }

    public func load() async -> QuotaSnapshotLoad {
        async let codex = loadCodex()
        async let claude = loadClaude()
        let (codexResult, claudeResult) = await (codex, claude)
        return QuotaSnapshotLoad(
            snapshot: QuotaSnapshot(
                fetchedAt: now(),
                codexSummary: codexResult.summary,
                codexErrorMessage: codexResult.errorMessage,
                claudeSummary: claudeResult.summary,
                claudeErrorMessage: claudeResult.errorMessage
            )
        )
    }

    private func loadCodex() async -> CodexLoadResult {
        do {
            let accounts = try await client.fetchAccounts()
            return CodexLoadResult(
                summary: QuotaCalculator.summarize(accounts: accounts),
                errorMessage: nil
            )
        } catch {
            return CodexLoadResult(summary: nil, errorMessage: error.localizedDescription)
        }
    }

    private func loadClaude() async -> ClaudeLoadResult {
        do {
            let accounts = try await client.fetchClaudeAccounts()
            return ClaudeLoadResult(
                summary: ClaudeQuotaCalculator.summarize(accounts: accounts),
                errorMessage: nil
            )
        } catch {
            return ClaudeLoadResult(summary: nil, errorMessage: error.localizedDescription)
        }
    }
}

private struct CodexLoadResult: Sendable {
    let summary: QuotaSummary?
    let errorMessage: String?
}

private struct ClaudeLoadResult: Sendable {
    let summary: ClaudeQuotaSummary?
    let errorMessage: String?
}
