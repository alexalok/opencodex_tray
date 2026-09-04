import Foundation

public struct TrayConfiguration: Equatable, Sendable {
    public let baseURL: URL
    public let adminTokenPath: String
    public let pollInterval: TimeInterval
    public let requestTimeout: TimeInterval

    public static func load(
        environment: [String: String],
        configFileURL: URL? = nil
    ) throws -> TrayConfiguration {
        let fileURL = configFileURL ?? defaultConfigFileURL(environment: environment)
        var merged = environment
        if FileManager.default.fileExists(atPath: fileURL.path) {
            let file: ConfigurationFile
            do {
                file = try JSONDecoder().decode(ConfigurationFile.self, from: Data(contentsOf: fileURL))
            } catch {
                throw ConfigurationError.invalid("Quota tray config file is invalid JSON")
            }
            if merged["POLL_INTERVAL_MS"] == nil, let value = file.pollIntervalMS { merged["POLL_INTERVAL_MS"] = String(value) }
            if merged["REQUEST_TIMEOUT_MS"] == nil, let value = file.requestTimeoutMS { merged["REQUEST_TIMEOUT_MS"] = String(value) }
            if merged["OPENCODEX_BASE_URL"] == nil { merged["OPENCODEX_BASE_URL"] = file.openCodexBaseURL }
            if merged["OPENCODEX_HOME"] == nil { merged["OPENCODEX_HOME"] = file.openCodexHome }
        }
        return try resolve(environment: merged)
    }

    public static func resolve(environment: [String: String]) throws -> TrayConfiguration {
        guard let home = environment["OPENCODEX_HOME"] ?? environment["HOME"].map({ "\($0)/.opencodex" }) else {
            throw ConfigurationError.invalid("HOME or OPENCODEX_HOME is required")
        }
        let rawURL = environment["OPENCODEX_BASE_URL"] ?? "http://127.0.0.1:10100"
        guard let url = URL(string: rawURL), let scheme = url.scheme?.lowercased(), let host = url.host else {
            throw ConfigurationError.invalid("OPENCODEX_BASE_URL must be a valid URL")
        }
        guard scheme == "http" || scheme == "https" else {
            throw ConfigurationError.invalid("OPENCODEX_BASE_URL must use http or https")
        }
        guard url.user == nil, url.password == nil else {
            throw ConfigurationError.invalid("OPENCODEX_BASE_URL must not include credentials")
        }
        let loopback = isLoopbackHost(host)
        guard scheme == "https" || loopback else {
            throw ConfigurationError.invalid("OPENCODEX_BASE_URL must use https for non-loopback hosts")
        }
        guard url.path.isEmpty || url.path == "/", url.query == nil, url.fragment == nil else {
            throw ConfigurationError.invalid("OPENCODEX_BASE_URL must not include a path, query, or fragment")
        }

        let pollMS = try integer(environment["POLL_INTERVAL_MS"], default: 60_000, name: "POLL_INTERVAL_MS")
        let timeoutMS = try integer(environment["REQUEST_TIMEOUT_MS"], default: 30_000, name: "REQUEST_TIMEOUT_MS")

        return TrayConfiguration(
            baseURL: url,
            adminTokenPath: URL(fileURLWithPath: home).appendingPathComponent("admin-api-token").path,
            pollInterval: Double(pollMS) / 1_000,
            requestTimeout: Double(timeoutMS) / 1_000
        )
    }

    private static func integer(_ raw: String?, default fallback: Int, name: String) throws -> Int {
        guard let raw, !raw.isEmpty else { return fallback }
        guard let value = Int(raw), value >= 1_000 else {
            throw ConfigurationError.invalid("\(name) must be an integer of at least 1000")
        }
        return value
    }

    private static func defaultConfigFileURL(environment: [String: String]) -> URL {
        let root = environment["XDG_CONFIG_HOME"]
            ?? environment["HOME"].map { "\($0)/.config" }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config").path
        return URL(fileURLWithPath: root)
            .appendingPathComponent("opencodex-quota-tray")
            .appendingPathComponent("config.json")
    }

    private static func isLoopbackHost(_ host: String) -> Bool {
        if host == "localhost" || host == "::1" { return true }
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count == 4 else { return false }
        let octets = labels.map { Int($0) }
        guard octets.allSatisfy({ $0 != nil }) else { return false }
        let values = octets.compactMap { $0 }
        return values[0] == 127 && values.allSatisfy { (0...255).contains($0) }
    }
}

private struct ConfigurationFile: Decodable {
    let pollIntervalMS: Int?
    let requestTimeoutMS: Int?
    let openCodexBaseURL: String?
    let openCodexHome: String?
}

public enum ConfigurationError: Error, LocalizedError, Equatable, Sendable {
    case invalid(String)
    public var errorDescription: String? {
        switch self { case let .invalid(message): message }
    }
}

public enum AdminTokenReader {
    public static func read(path: String) throws -> String {
        let attributes = try FileManager.default.attributesOfItem(atPath: path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              (attributes[.size] as? NSNumber)?.intValue ?? 513 <= 512 else {
            throw ConfigurationError.invalid("Admin token path must be a regular file of at most 512 bytes")
        }
        let token = try String(contentsOfFile: path, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { throw ConfigurationError.invalid("Admin token file is empty") }
        return token
    }
}
