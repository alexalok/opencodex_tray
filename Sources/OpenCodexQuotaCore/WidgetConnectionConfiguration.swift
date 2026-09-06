import Foundation

public struct WidgetConnectionConfiguration: Codable, Equatable, Sendable {
    public let baseURL: URL
    public let adminToken: String
    public let requestTimeout: TimeInterval

    public init(
        baseURL: URL,
        adminToken: String,
        requestTimeout: TimeInterval
    ) {
        self.baseURL = baseURL
        self.adminToken = adminToken
        self.requestTimeout = requestTimeout
    }
}

public struct WidgetConfigurationStore: Sendable {
    // macOS App Group IDs are coupled to the signing certificate's Team ID.
    public static let appGroupIdentifier = "KTNPDHXXV3.opencodex.quota-tray.shared"

    public let fileURL: URL

    public init(containerURL: URL) {
        fileURL = containerURL
            .appendingPathComponent("Configuration", isDirectory: true)
            .appendingPathComponent("widget-connection.json")
    }

    public static func shared(
        fileManager: FileManager = .default
    ) throws -> WidgetConfigurationStore {
        guard let containerURL = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) else {
            throw ConfigurationError.invalid("App Group container is unavailable")
        }
        return WidgetConfigurationStore(containerURL: containerURL)
    }

    public func save(
        _ configuration: WidgetConnectionConfiguration,
        fileManager: FileManager = .default
    ) throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try fileManager.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: directoryURL.path
        )
        try JSONEncoder().encode(configuration).write(to: fileURL, options: .atomic)
        try fileManager.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: fileURL.path
        )
    }

    public func load() throws -> WidgetConnectionConfiguration {
        try JSONDecoder().decode(
            WidgetConnectionConfiguration.self,
            from: Data(contentsOf: fileURL)
        )
    }
}
