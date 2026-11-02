import Foundation

public struct AdaptiveQuotaSnapshotLoader: QuotaSnapshotLoading {
    private let configuration: TrayConfiguration?
    private let connection: QuotaConnection?
    private let timeout: TimeInterval
    private let http: any QuotaHTTPServing
    private let publish: @Sendable (QuotaConnection) throws -> Void

    /// Main app: re-read the host configuration and credential on every refresh.
    public init(configuration: TrayConfiguration,
                publish: @escaping @Sendable (QuotaConnection) throws -> Void = { _ in }) {
        self.configuration = configuration
        connection = nil
        timeout = configuration.requestTimeout
        http = QuotaHTTPClient(timeout: timeout)
        self.publish = publish
    }

    /// Widget: use the shared connection only after checking the host's live enrollment.
    public init(connection: QuotaConnection, timeout: TimeInterval, http: (any QuotaHTTPServing)? = nil) {
        configuration = nil
        self.connection = connection
        self.timeout = timeout
        self.http = http ?? QuotaHTTPClient(timeout: timeout)
        publish = { _ in }
    }

    public func load() async -> QuotaSnapshotLoad {
        var resolved: QuotaConnection?
        do {
            let probe = QuotaHostProbe(http: http)
            let source: QuotaConnection
            if let configuration {
                let role = try await probe.role(at: configuration.baseURL)
                source = try Self.resolve(configuration, role: role)
            } else if let connection { source = connection }
            else { throw ConfigurationError.invalid("Open tray to refresh quota connection") }
            resolved = source
            let headers = try await probe.validate(source)
            try publish(source)
            let snapshot: QuotaSnapshot
            if source.mode == .hub {
                let data = try await http.get(source.sourceURL.appendingPathComponent("v1/hub-quota"),
                    headers: ["x-opencodex-api-key": source.token, "Accept": "application/json"])
                snapshot = try HubQuotaDecoder.decode(data)
            } else if source.mode == .link {
                snapshot = await QuotaSnapshotLoader(client: LinkQuotaClient(host: source.hostURL, headers: headers, http: http)).load().snapshot
            } else {
                let client = EnabledLocalClient(client: OpenCodexClient(baseURL: source.sourceURL, adminToken: source.token, timeout: timeout),
                    codexEnabled: source.codexEnabled, claudeEnabled: source.claudeEnabled)
                snapshot = await QuotaSnapshotLoader(client: client).load().snapshot
            }
            // Discard a response completed after the host changed enrollment or local files.
            try await probe.validate(source)
            if let configuration {
                let role = try await probe.role(at: configuration.baseURL)
                guard try Self.resolve(configuration, role: role) == source else {
                    throw ConfigurationError.invalid("OpenCodex config changed during quota refresh; retry")
                }
            }
            return QuotaSnapshotLoad(snapshot: QuotaSnapshot(sourceID: source.sourceID, sourceLabel: source.label,
                codexEnabled: snapshot.codexEnabled ?? source.codexEnabled,
                claudeEnabled: snapshot.claudeEnabled ?? source.claudeEnabled,
                fetchedAt: snapshot.fetchedAt, codexSummary: snapshot.codexSummary, codexErrorMessage: snapshot.codexErrorMessage,
                claudeSummary: snapshot.claudeSummary, claudeErrorMessage: snapshot.claudeErrorMessage))
        } catch {
            return QuotaSnapshotLoad(snapshot: QuotaSnapshot(sourceID: resolved?.sourceID, sourceLabel: resolved?.label,
                discardCachedData: true, fetchedAt: Date(), codexSummary: nil, codexErrorMessage: error.localizedDescription,
                claudeSummary: nil, claudeErrorMessage: error.localizedDescription))
        }
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

private struct EnabledLocalClient: OpenCodexQuotaServing {
    let client: OpenCodexClient
    let codexEnabled: Bool
    let claudeEnabled: Bool
    func fetchAccounts() async throws -> [OpenCodexAccount] { try await codexEnabled ? client.fetchAccounts() : [] }
    func fetchClaudeAccounts() async throws -> [ClaudeAccount] { try await claudeEnabled ? client.fetchClaudeAccounts() : [] }
}

/// The Child authenticates the tunnel. Only its local GUI session is sent here.
private struct LinkQuotaClient: OpenCodexQuotaServing {
    let host: URL
    let headers: [String: String]
    let http: any QuotaHTTPServing

    private func read(_ path: String) async throws -> Data {
        let url = URL(string: "/api/machine/hub-relay" + path, relativeTo: host)!.absoluteURL
        return try await http.get(url, headers: headers)
    }
    func fetchAccounts() async throws -> [OpenCodexAccount] {
        let accounts = try await read("/api/codex-auth/accounts")
        let active = try? await read("/api/codex-auth/active")
        let threshold = active.flatMap { try? JSONDecoder().decode(LinkActiveAccount.self, from: $0).autoSwitchThreshold?.value }
        return try OpenCodexResponseDecoder.decodeAccounts(accounts, globalAutoSwitchThreshold: threshold)
    }
    func fetchClaudeAccounts() async throws -> [ClaudeAccount] {
        let data = try await read("/api/oauth/accounts?provider=anthropic")
        let accounts = try OpenCodexResponseDecoder.decodeClaudeAccounts(data)
        // Provider reports identify no account. Only use one for a single, stable active account.
        guard accounts.count == 1, let account = accounts.first,
              account.fiveHourUsedPercent == nil, account.weeklyUsedPercent == nil,
              try JSONDecoder().decode(LinkAccountSelection.self, from: data).activeAccountId == account.id else { return accounts }
        let reports = try JSONDecoder().decode(LinkProviderReports.self, from: await read("/api/provider-quotas"))
        let currentData = try await read("/api/oauth/accounts?provider=anthropic")
        guard try JSONDecoder().decode(LinkAccountSelection.self, from: currentData).activeAccountId == account.id,
              try OpenCodexResponseDecoder.decodeClaudeAccounts(currentData) == accounts,
              let quota = reports.reports.first(where: { $0.provider == "anthropic" && $0.source == "anthropic:oauth-usage" })?.quota else { return accounts }
        return [ClaudeAccount(id: account.id, alias: account.alias, email: account.email,
            fiveHourUsedPercent: quota.fiveHourPercent, weeklyUsedPercent: quota.weeklyPercent)]
    }
}
private struct LinkActiveAccount: Decodable {
    struct Threshold: Decodable {
        let value: Double?
        init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let number = try? container.decode(Double.self), number.isFinite,
               number.rounded() == number, (0...100).contains(number) { value = number }
            else { value = nil }
        }
    }
    let autoSwitchThreshold: Threshold?
}

private struct LinkAccountSelection: Decodable { let activeAccountId: String? }
private struct LinkProviderReports: Decodable {
    struct Report: Decodable {
        struct Quota: Decodable { let fiveHourPercent: Double?; let weeklyPercent: Double? }
        let provider: String
        let source: String?
        let quota: Quota?
    }
    let reports: [Report]
}
