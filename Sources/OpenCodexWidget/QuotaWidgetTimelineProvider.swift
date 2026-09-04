import Foundation
import OSLog
import PauseWorkerCore
import WidgetKit

struct QuotaWidgetEntry: TimelineEntry, Equatable {
    let date: Date
    let content: QuotaWidgetContent
    let isPlaceholder: Bool
}

struct QuotaWidgetTimelineResult: Equatable {
    let entry: QuotaWidgetEntry
    let nextRefresh: Date
}

struct QuotaWidgetTimelineService {
    private static let logger = Logger(
        subsystem: "local.opencodex.quota-tray.widget",
        category: "timeline"
    )

    let makeLoader: @Sendable () throws -> any QuotaSnapshotLoading
    let cache: any WidgetSnapshotCaching
    let now: @Sendable () -> Date

    func makeEntry() async -> QuotaWidgetTimelineResult {
        let date = now()
        let cached = await cache.load()
        let load: QuotaSnapshotLoad?

        do {
            let loader = try makeLoader()
            load = await loader.load()
        } catch {
            Self.logger.error(
                "Failed to create quota loader: \(error.localizedDescription, privacy: .public)"
            )
            load = nil
        }

        if let snapshot = load?.snapshot, !snapshot.hasProviderData {
            Self.logger.error(
                "Quota fetch failed. Codex: \(snapshot.codexErrorMessage ?? "none", privacy: .public); Claude: \(snapshot.claudeErrorMessage ?? "none", privacy: .public)"
            )
        }

        let resolution = QuotaWidgetStateResolver.resolve(load: load, cached: cached)
        if let snapshot = resolution.snapshotToCache {
            try? await cache.save(snapshot)
        }

        return QuotaWidgetTimelineResult(
            entry: QuotaWidgetEntry(
                date: date,
                content: resolution.content,
                isPlaceholder: false
            ),
            nextRefresh: date.addingTimeInterval(30 * 60)
        )
    }
}

struct QuotaWidgetTimelineProvider: TimelineProvider {
    private let service: QuotaWidgetTimelineService
    private let cache: any WidgetSnapshotCaching

    init() {
        let cache = WidgetSnapshotCache()
        self.init(
            service: QuotaWidgetTimelineService(
                makeLoader: { try Self.makeProductionLoader() },
                cache: cache,
                now: { Date() }
            ),
            cache: cache
        )
    }

    init(service: QuotaWidgetTimelineService, cache: any WidgetSnapshotCaching) {
        self.service = service
        self.cache = cache
    }

    static func placeholderEntry(at date: Date) -> QuotaWidgetEntry {
        let snapshot = QuotaSnapshot(
            fetchedAt: date,
            codexSummary: QuotaSummary(
                trayPercentage: 68,
                rows: [
                    AccountAllowance(
                        accountId: "codex-main",
                        label: "main",
                        remainingPercent: 68,
                        totalPercent: 100
                    ),
                ]
            ),
            codexErrorMessage: nil,
            claudeSummary: ClaudeQuotaSummary(
                fiveHourRemainingPercentage: 97,
                weeklyRemainingPercentage: 88,
                rows: [
                    ClaudeAccountAllowance(
                        accountId: "claude-work",
                        label: "work",
                        fiveHourRemainingPercent: 97,
                        weeklyRemainingPercent: 88
                    ),
                ]
            ),
            claudeErrorMessage: nil
        )
        return QuotaWidgetEntry(
            date: date,
            content: .snapshot(snapshot, stale: false),
            isPlaceholder: true
        )
    }

    func snapshotEntry(at date: Date) async -> QuotaWidgetEntry {
        guard let cached = await cache.load() else {
            return Self.placeholderEntry(at: date)
        }
        return QuotaWidgetEntry(
            date: date,
            content: .snapshot(cached, stale: true),
            isPlaceholder: false
        )
    }

    func placeholder(in context: Context) -> QuotaWidgetEntry {
        Self.placeholderEntry(at: .now)
    }

    func getSnapshot(
        in context: Context,
        completion: @escaping @Sendable (QuotaWidgetEntry) -> Void
    ) {
        Task {
            completion(await snapshotEntry(at: .now))
        }
    }

    func getTimeline(
        in context: Context,
        completion: @escaping @Sendable (Timeline<QuotaWidgetEntry>) -> Void
    ) {
        Task {
            let result = await service.makeEntry()
            completion(
                Timeline(
                    entries: [result.entry],
                    policy: .after(result.nextRefresh)
                )
            )
        }
    }

    private static func makeProductionLoader() throws -> any QuotaSnapshotLoading {
        let config = try WidgetConfigurationStore.shared().load()
        let client = OpenCodexQuotaClient(
            baseURL: config.baseURL,
            adminToken: config.adminToken,
            timeout: config.requestTimeout
        )
        return QuotaSnapshotLoader(
            client: client,
            targetAlias: config.targetAlias,
            thresholdPercent: config.thresholdPercent
        )
    }
}
