public struct QuotaRefresh: Equatable, Sendable {
    public let codexSummary: QuotaSummary
    public let claudeSummary: ClaudeQuotaSummary?
    public let claudeErrorMessage: String?
}

public actor QuotaRefresher {
    private let client: any OpenCodexQuotaServing
    private var inFlightRefresh: Task<QuotaRefresh, Error>?

    public init(client: any OpenCodexQuotaServing) {
        self.client = client
    }

    public func refresh() async throws -> QuotaRefresh {
        if let inFlightRefresh { return try await inFlightRefresh.value }

        let task = Task { [client] in
            async let claudeRefresh = fetchClaudeSummary(client: client)
            let accounts = try await client.fetchAccounts()
            let codexSummary = QuotaCalculator.summarize(accounts: accounts)
            let claude = await claudeRefresh
            return QuotaRefresh(
                codexSummary: codexSummary,
                claudeSummary: claude.summary,
                claudeErrorMessage: claude.errorMessage
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
    let errorMessage: String?
}

private func fetchClaudeSummary(client: any OpenCodexQuotaServing) async -> ClaudeRefreshResult {
    do {
        let accounts = try await client.fetchClaudeAccounts()
        return ClaudeRefreshResult(
            summary: ClaudeQuotaCalculator.summarize(accounts: accounts),
            errorMessage: nil
        )
    } catch {
        return ClaudeRefreshResult(summary: nil, errorMessage: error.localizedDescription)
    }
}
