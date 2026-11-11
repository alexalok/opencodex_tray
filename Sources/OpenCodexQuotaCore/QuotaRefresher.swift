public actor QuotaRefresher {
    private let loader: any TrayQuotaLoading
    private var inFlightRefresh: Task<TrayQuotaLoad, Never>?

    public init(loader: any TrayQuotaLoading) {
        self.loader = loader
    }

    public func refresh() async -> TrayQuotaLoad {
        if let inFlightRefresh { return await inFlightRefresh.value }

        let task = Task { [loader] in await loader.load() }
        inFlightRefresh = task
        let result = await task.value
        inFlightRefresh = nil
        return result
    }
}
