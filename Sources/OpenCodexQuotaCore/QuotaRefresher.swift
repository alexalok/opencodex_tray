public actor QuotaRefresher {
    private let loader: any QuotaSnapshotLoading
    private var inFlightRefresh: Task<QuotaSnapshotLoad, Never>?

    public init(loader: any QuotaSnapshotLoading) {
        self.loader = loader
    }

    public func refresh() async -> QuotaSnapshotLoad {
        if let inFlightRefresh { return await inFlightRefresh.value }

        let task = Task { [loader] in await loader.load() }
        inFlightRefresh = task
        let result = await task.value
        inFlightRefresh = nil
        return result
    }
}
