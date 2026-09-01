import Foundation
import PauseWorkerCore

enum QuotaWidgetContent: Equatable, Sendable {
    case snapshot(QuotaSnapshot, stale: Bool)
    case unavailable
}

struct QuotaWidgetResolution: Equatable, Sendable {
    let content: QuotaWidgetContent
    let snapshotToCache: QuotaSnapshot?
}

enum QuotaWidgetStateResolver {
    static func resolve(
        load: QuotaSnapshotLoad?,
        cached: QuotaSnapshot?
    ) -> QuotaWidgetResolution {
        guard let snapshot = load?.snapshot, snapshot.hasProviderData else {
            return QuotaWidgetResolution(
                content: cached.map { .snapshot($0, stale: true) } ?? .unavailable,
                snapshotToCache: nil
            )
        }

        return QuotaWidgetResolution(
            content: .snapshot(snapshot, stale: false),
            snapshotToCache: snapshot.isComplete ? snapshot : nil
        )
    }
}

struct QuotaWidgetRowModel: Equatable, Identifiable {
    let id: String
    let label: String
    let value: String
}

struct QuotaWidgetProviderModel: Equatable {
    let total: String
    let rows: [QuotaWidgetRowModel]
    let overflowCount: Int
    let isUnavailable: Bool
}

struct QuotaWidgetViewModel: Equatable {
    let codex: QuotaWidgetProviderModel
    let claude: QuotaWidgetProviderModel
    let updatedAt: Date?
    let isStale: Bool
    let isUnavailable: Bool

    init(content: QuotaWidgetContent) {
        switch content {
        case .unavailable:
            codex = Self.unavailableProvider
            claude = Self.unavailableProvider
            updatedAt = nil
            isStale = false
            isUnavailable = true
        case let .snapshot(snapshot, stale):
            codex = snapshot.codexSummary.map(Self.codexProvider) ?? Self.unavailableProvider
            claude = snapshot.claudeSummary.map(Self.claudeProvider) ?? Self.unavailableProvider
            updatedAt = snapshot.fetchedAt
            isStale = stale
            isUnavailable = false
        }
    }

    private static let unavailableProvider = QuotaWidgetProviderModel(
        total: "Unavailable",
        rows: [],
        overflowCount: 0,
        isUnavailable: true
    )

    private static func codexProvider(_ summary: QuotaSummary) -> QuotaWidgetProviderModel {
        QuotaWidgetProviderModel(
            total: DisplayFormatter.trayTitle(summary.trayPercentage),
            rows: summary.rows.prefix(2).map {
                QuotaWidgetRowModel(
                    id: $0.id,
                    label: $0.label,
                    value: DisplayFormatter.codexAllowance($0)
                )
            },
            overflowCount: max(summary.rows.count - 2, 0),
            isUnavailable: false
        )
    }

    private static func claudeProvider(
        _ summary: ClaudeQuotaSummary
    ) -> QuotaWidgetProviderModel {
        QuotaWidgetProviderModel(
            total: DisplayFormatter.claudeTrayTitle(summary),
            rows: summary.rows.prefix(2).map {
                QuotaWidgetRowModel(
                    id: $0.id,
                    label: $0.label,
                    value: DisplayFormatter.claudeAllowance($0)
                )
            },
            overflowCount: max(summary.rows.count - 2, 0),
            isUnavailable: false
        )
    }
}
