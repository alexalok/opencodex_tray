import Foundation
import PauseWorkerCore

protocol WidgetSnapshotCaching: Sendable {
    func load() async -> QuotaSnapshot?
    func save(_ snapshot: QuotaSnapshot) async throws
}

actor WidgetSnapshotCache: WidgetSnapshotCaching {
    private let fileURL: URL

    init(fileURL: URL = WidgetSnapshotCache.defaultFileURL()) {
        self.fileURL = fileURL
    }

    func load() async -> QuotaSnapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(QuotaSnapshot.self, from: data)
    }

    func save(_ snapshot: QuotaSnapshot) async throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try JSONEncoder().encode(snapshot).write(to: fileURL, options: .atomic)
    }

    private static func defaultFileURL() -> URL {
        FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        .appendingPathComponent("OpenCodexWidget", isDirectory: true)
        .appendingPathComponent("quota-snapshot.json")
    }
}
