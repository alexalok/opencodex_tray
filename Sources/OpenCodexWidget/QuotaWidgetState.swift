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
