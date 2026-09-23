import Foundation

public protocol OpenCodexQuotaServing: Sendable {
    func fetchAccounts() async throws -> [OpenCodexAccount]
    func fetchClaudeAccounts() async throws -> [ClaudeAccount]
}

public actor OpenCodexClient: OpenCodexQuotaServing {
    private let baseURL: URL
    private let adminToken: String
    private let session: URLSession

    public init(baseURL: URL, adminToken: String, timeout: TimeInterval, session: URLSession? = nil) {
        self.baseURL = baseURL
        self.adminToken = adminToken
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = timeout
            self.session = URLSession(configuration: configuration)
        }
    }

    public func fetchAccounts() async throws -> [OpenCodexAccount] {
        var request = URLRequest(url: endpoint("/api/codex-auth/accounts?refresh=1"))
        request.httpMethod = "GET"
        request.setValue("Bearer \(adminToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let data = try await send(request, operation: "accounts")
        // Public/older servers may omit this optional setting or endpoint entirely.
        let globalThreshold = await fetchGlobalAutoSwitchThreshold()
        do {
            return try OpenCodexResponseDecoder.decodeAccounts(data, globalAutoSwitchThreshold: globalThreshold)
        } catch {
            throw OpenCodexClientError.invalidResponse("OpenCodex returned an invalid account response")
        }
    }

    private func fetchGlobalAutoSwitchThreshold() async -> Double? {
        var request = URLRequest(url: endpoint("/api/codex-auth/active"))
        request.httpMethod = "GET"
        request.setValue("Bearer \(adminToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let data = try? await send(request, operation: "auto-switch settings"),
              let settings = try? JSONDecoder().decode(ActiveAccountResponse.self, from: data) else {
            return nil
        }
        return settings.autoSwitchThreshold?.value
    }

    public func fetchClaudeAccounts() async throws -> [ClaudeAccount] {
        var request = URLRequest(url: endpoint("/api/oauth/accounts?provider=anthropic&quota=1&refresh=1"))
        request.httpMethod = "GET"
        request.setValue("Bearer \(adminToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let data = try await send(request, operation: "Claude accounts")
        do {
            return try OpenCodexResponseDecoder.decodeClaudeAccounts(data)
        } catch {
            throw OpenCodexClientError.invalidResponse("OpenCodex returned an invalid Claude account response")
        }
    }

    private func endpoint(_ path: String) -> URL {
        URL(string: path, relativeTo: baseURL)!.absoluteURL
    }

    private func send(_ request: URLRequest, operation: String) async throws -> Data {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw OpenCodexClientError.invalidResponse("OpenCodex returned a non-HTTP response")
            }
            guard (200..<300).contains(http.statusCode) else {
                throw OpenCodexClientError.http(operation: operation, status: http.statusCode)
            }
            return data
        } catch let error as OpenCodexClientError {
            throw error
        } catch {
            throw OpenCodexClientError.network("OpenCodex request failed")
        }
    }
}

public enum OpenCodexResponseDecoder {
    public static func decodeAccounts(
        _ data: Data,
        globalAutoSwitchThreshold: Double? = nil
    ) throws -> [OpenCodexAccount] {
        let accounts = try JSONDecoder().decode(AccountsResponse.self, from: data).accounts
        let poolMatches = accounts.filter { $0.isMain != true }.compactMap(\.quotaMatch)
        return accounts.filter { dto in
            guard dto.isMain == true, let match = dto.quotaMatch else { return true }
            // The named pool entry owns display and pause state for duplicate main logins.
            return !poolMatches.contains { $0.matches(match) }
        }.map { dto in
            OpenCodexAccount(
                id: dto.id,
                alias: dto.alias,
                plan: dto.plan,
                isMain: dto.isMain ?? false,
                paused: dto.paused ?? false,
                weeklyUsedPercent: dto.quota?.weeklyPercent,
                autoSwitchThreshold: dto.autoSwitchThresholdOverride?.value ?? globalAutoSwitchThreshold
            )
        }
    }

    public static func decodeClaudeAccounts(_ data: Data) throws -> [ClaudeAccount] {
        try JSONDecoder().decode(ClaudeAccountsResponse.self, from: data).accounts.map { dto in
            ClaudeAccount(
                id: dto.id,
                alias: dto.alias,
                email: dto.email,
                fiveHourUsedPercent: dto.quota?.fiveHourPercent,
                weeklyUsedPercent: dto.quota?.weeklyPercent
            )
        }
    }
}

public enum OpenCodexClientError: Error, LocalizedError, Sendable {
    case network(String)
    case http(operation: String, status: Int)
    case invalidResponse(String)

    public var errorDescription: String? {
        switch self {
        case let .network(message), let .invalidResponse(message): message
        case let .http(operation, status): "OpenCodex \(operation) request failed with HTTP \(status)"
        }
    }
}

private struct AccountsResponse: Decodable { let accounts: [AccountDTO] }
private struct AccountDTO: Decodable {
    let id: String
    let alias: String?
    let email: String?
    let plan: String?
    let isMain: Bool?
    let paused: Bool?
    let autoSwitchThresholdOverride: AutoSwitchThresholdDTO?
    let quota: QuotaDTO?

    var quotaMatch: AccountQuotaMatch? {
        // OpenCodex omits upstream account IDs and may mask email addresses.
        // Require the same subscription and reset window before hiding main;
        // usage percentages can differ between independently refreshed copies.
        guard let email = email?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              email.contains("@"),
              let plan = plan?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !plan.isEmpty,
              let weeklyResetAt = quota?.weeklyResetAt, weeklyResetAt > 0 else { return nil }
        return AccountQuotaMatch(email: email, plan: plan, weeklyResetAt: weeklyResetAt)
    }
}
private struct AccountQuotaMatch {
    let email: String
    let plan: String
    let weeklyResetAt: Double

    func matches(_ other: AccountQuotaMatch) -> Bool {
        // Streaming headers and the usage API can report the same reset a second apart.
        // Compare directly: rounding into buckets would still fail at bucket boundaries.
        email == other.email && plan == other.plan
            && abs(weeklyResetAt - other.weeklyResetAt) <= 2
    }
}
private struct QuotaDTO: Decodable {
    let fiveHourPercent: Double?
    let weeklyPercent: Double?
    let weeklyResetAt: Double?
}
private struct ClaudeAccountsResponse: Decodable { let accounts: [ClaudeAccountDTO] }
private struct ClaudeAccountDTO: Decodable {
    let id: String
    let alias: String?
    let email: String?
    let quota: QuotaDTO?
}

private struct ActiveAccountResponse: Decodable {
    let autoSwitchThreshold: AutoSwitchThresholdDTO?
}

/// Optional extension fields must never invalidate an otherwise usable account response.
private struct AutoSwitchThresholdDTO: Decodable {
    let value: Double?

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let number = try? container.decode(Double.self),
           number.isFinite, number.rounded() == number, (0...100).contains(number) {
            value = number
        } else {
            value = nil
        }
    }
}
