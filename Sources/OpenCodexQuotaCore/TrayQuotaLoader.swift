import Foundation

public struct TrayQuotaLoad: Equatable, Sendable {
    public let quota: TrayQuota?
    public let sourceLabel: String?
    public let errorMessage: String?

    public init(quota: TrayQuota?, sourceLabel: String?, errorMessage: String? = nil) {
        self.quota = quota
        self.sourceLabel = sourceLabel
        self.errorMessage = errorMessage
    }
}

public protocol TrayQuotaLoading: Sendable {
    func load() async -> TrayQuotaLoad
}

/// One read per refresh in steady state: the host's role and enrollment are checked once and
/// reused while the resolved connection (local config files) is unchanged and reads succeed. A
/// failed read with reused credentials is retried once after a full check.
public actor TrayQuotaLoader: TrayQuotaLoading {
    public typealias Resolve = @Sendable (_ role: String) throws -> QuotaConnection

    private struct Verified {
        let role: String
        let connection: QuotaConnection
        let headers: [String: String]
    }

    private let baseURL: URL
    private let http: any QuotaHTTPServing
    private let resolve: Resolve
    private var verified: Verified?

    public init(configuration: TrayConfiguration) {
        self.init(baseURL: configuration.baseURL, http: QuotaHTTPClient(timeout: configuration.requestTimeout)) { role in
            try Self.resolve(configuration, role: role)
        }
    }

    init(baseURL: URL, http: any QuotaHTTPServing, resolve: @escaping Resolve) {
        self.baseURL = baseURL
        self.http = http
        self.resolve = resolve
    }

    public func load() async -> TrayQuotaLoad {
        if let verified, let current = try? resolve(verified.role), current == verified.connection,
           let quota = try? await read(verified) {
            return TrayQuotaLoad(quota: quota, sourceLabel: verified.connection.label)
        }
        verified = nil
        var label: String?
        do {
            let probe = QuotaHostProbe(http: http)
            let role = try await probe.role(at: baseURL)
            let connection = try resolve(role)
            label = connection.label
            let session = try await probe.validate(connection)
            let headers = connection.mode == .local
                ? ["Authorization": "Bearer \(connection.token)", "Accept": "application/json"]
                : session.merging(["Accept": "application/json"]) { current, _ in current }
            let fresh = Verified(role: role, connection: connection, headers: headers)
            let quota = try await read(fresh)
            verified = fresh
            return TrayQuotaLoad(quota: quota, sourceLabel: label)
        } catch {
            return TrayQuotaLoad(quota: nil, sourceLabel: label, errorMessage: error.localizedDescription)
        }
    }

    private func read(_ source: Verified) async throws -> TrayQuota {
        let path = source.connection.mode == .local ? "/api/quota-pool/tray" : "/api/machine/hub-relay/api/quota-pool/tray"
        let url = URL(string: path, relativeTo: source.connection.hostURL)!.absoluteURL
        return try TrayQuota.decode(await http.get(url, headers: source.headers))
    }

    private static func resolve(_ configuration: TrayConfiguration, role: String) throws -> QuotaConnection {
        let home = URL(fileURLWithPath: configuration.adminTokenPath).deletingLastPathComponent()
        let path = home.appendingPathComponent("config.json")
        let data = FileManager.default.fileExists(atPath: path.path) ? try Data(contentsOf: path) : nil
        return try QuotaConnection.resolve(hostURL: configuration.baseURL, runningRole: role, configData: data,
            adminToken: try? AdminTokenReader.read(path: configuration.adminTokenPath),
            dataToken: try? AdminTokenReader.read(path: home.appendingPathComponent("service-api-token").path))
    }
}
