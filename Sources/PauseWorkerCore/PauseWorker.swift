public struct WorkerRefresh: Equatable, Sendable {
    public let snapshot: QuotaSnapshot
    public let pausedAccountID: String?

    public init(snapshot: QuotaSnapshot, pausedAccountID: String?) {
        self.snapshot = snapshot
        self.pausedAccountID = pausedAccountID
    }
}

public actor PauseWorker {
    private let loader: any QuotaSnapshotLoading
    private let pauser: any OpenCodexPausing
    private let targetAlias: String
    private let thresholdPercent: Double
    private var inFlightRefresh: Task<WorkerRefresh, Error>?

    public init(
        loader: any QuotaSnapshotLoading,
        pauser: any OpenCodexPausing,
        targetAlias: String,
        thresholdPercent: Double
    ) {
        self.loader = loader
        self.pauser = pauser
        self.targetAlias = targetAlias
        self.thresholdPercent = thresholdPercent
    }

    public func refresh() async throws -> WorkerRefresh {
        if let inFlightRefresh { return try await inFlightRefresh.value }

        let task = Task { [loader, pauser, targetAlias, thresholdPercent] in
            let load = await loader.load()
            let pausedAccountID: String?
            if let accounts = load.codexAccounts {
                let target = try targetAccount(alias: targetAlias, in: accounts)
                if !target.paused,
                   let used = target.weeklyUsedPercent,
                   used >= thresholdPercent {
                    try await pauser.pauseAccount(id: target.id)
                    pausedAccountID = target.id
                } else {
                    pausedAccountID = nil
                }
            } else {
                pausedAccountID = nil
            }
            return WorkerRefresh(
                snapshot: load.snapshot,
                pausedAccountID: pausedAccountID
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

private func targetAccount(
    alias: String,
    in accounts: [OpenCodexAccount]
) throws -> OpenCodexAccount {
    let matches = accounts.filter { $0.alias == alias }
    guard !matches.isEmpty else { throw QuotaError.targetAliasNotFound(alias) }
    guard matches.count == 1 else { throw QuotaError.duplicateTargetAlias(alias) }
    return matches[0]
}
