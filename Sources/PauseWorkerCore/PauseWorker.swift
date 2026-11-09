public struct WorkerRefresh: Equatable, Sendable {
    public let codexSummary: QuotaSummary
    public let claudeSummary: ClaudeQuotaSummary?
    public let claudeErrorMessage: String?
    public let pausedAccountID: String?
    let codexAccounts: [OpenCodexAccount]
    let claudeAccounts: [ClaudeAccount]?
    let targetAlias: String
    let thresholdPercent: Double

    public func normalized(using settings: SubscriptionSettings) throws -> WorkerRefresh {
        WorkerRefresh(
            codexSummary: try QuotaCalculator.summarize(accounts: codexAccounts,
                targetAlias: targetAlias, thresholdPercent: thresholdPercent, baseline: settings.codex),
            claudeSummary: claudeAccounts.map { ClaudeQuotaCalculator.summarize(accounts: $0, baseline: settings.claude) },
            claudeErrorMessage: claudeErrorMessage,
            pausedAccountID: pausedAccountID,
            codexAccounts: codexAccounts, claudeAccounts: claudeAccounts,
            targetAlias: targetAlias, thresholdPercent: thresholdPercent
        )
    }
}

public actor PauseWorker {
    private let client: any OpenCodexServing
    private let targetAlias: String
    private let thresholdPercent: Double
    private var inFlightRefresh: Task<WorkerRefresh, Error>?

    public init(client: any OpenCodexServing, targetAlias: String, thresholdPercent: Double) {
        self.client = client
        self.targetAlias = targetAlias
        self.thresholdPercent = thresholdPercent
    }

    public func refresh() async throws -> WorkerRefresh {
        if let inFlightRefresh { return try await inFlightRefresh.value }

        let task = Task { [client, targetAlias, thresholdPercent] in
            async let claudeRefresh = fetchClaudeSummary(client: client)
            let accounts = try await client.fetchAccounts()
            let codexSummary = try QuotaCalculator.summarize(
                accounts: accounts,
                targetAlias: targetAlias,
                thresholdPercent: thresholdPercent
            )
            let target = accounts.first { $0.alias == targetAlias }!
            let pausedAccountID: String?
            if !target.paused, let used = target.weeklyUsedPercent, used >= thresholdPercent {
                try await client.pauseAccount(id: target.id)
                pausedAccountID = target.id
            } else {
                pausedAccountID = nil
            }
            let claude = await claudeRefresh
            return WorkerRefresh(
                codexSummary: codexSummary,
                claudeSummary: claude.summary,
                claudeErrorMessage: claude.errorMessage,
                pausedAccountID: pausedAccountID,
                codexAccounts: accounts, claudeAccounts: claude.accounts,
                targetAlias: targetAlias, thresholdPercent: thresholdPercent
            )
        }
        inFlightRefresh = task
        do {
            let result = try await task.value
            inFlightRefresh = nil
            return result
        } catch {
            inFlightRefresh = nil
            throw error
        }
    }
}

private struct ClaudeRefreshResult: Sendable {
    let summary: ClaudeQuotaSummary?
    let accounts: [ClaudeAccount]?
    let errorMessage: String?
}

private func fetchClaudeSummary(client: any OpenCodexServing) async -> ClaudeRefreshResult {
    do {
        let accounts = try await client.fetchClaudeAccounts()
        return ClaudeRefreshResult(
            summary: ClaudeQuotaCalculator.summarize(accounts: accounts),
            accounts: accounts,
            errorMessage: nil
        )
    } catch {
        return ClaudeRefreshResult(summary: nil, accounts: nil, errorMessage: error.localizedDescription)
    }
}
