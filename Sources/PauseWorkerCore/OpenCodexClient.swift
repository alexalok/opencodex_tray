import Foundation

public protocol OpenCodexQuotaServing: Sendable {
    func fetchAccounts() async throws -> [OpenCodexAccount]
    func fetchClaudeAccounts() async throws -> [ClaudeAccount]
}

public protocol OpenCodexPausing: Sendable {
    func pauseAccount(id: String) async throws
}

public protocol OpenCodexServing: OpenCodexQuotaServing, OpenCodexPausing {}

public actor OpenCodexQuotaClient: OpenCodexQuotaServing {
    private let transport: OpenCodexTransport

    public init(baseURL: URL, adminToken: String, timeout: TimeInterval, session: URLSession? = nil) {
        transport = OpenCodexTransport(
            baseURL: baseURL,
            adminToken: adminToken,
            timeout: timeout,
            session: session
        )
    }

    public func fetchAccounts() async throws -> [OpenCodexAccount] {
        let data = try await transport.send(
            path: "/api/codex-auth/accounts?refresh=1",
            method: "GET",
            operation: "accounts"
        )
        do {
            return try OpenCodexResponseDecoder.decodeAccounts(data)
        } catch {
            throw OpenCodexClientError.invalidResponse("OpenCodex returned an invalid account response")
        }
    }

    public func fetchClaudeAccounts() async throws -> [ClaudeAccount] {
        let data = try await transport.send(
            path: "/api/oauth/accounts?provider=anthropic&quota=1&refresh=1",
            method: "GET",
            operation: "Claude accounts"
        )
        do {
            return try OpenCodexResponseDecoder.decodeClaudeAccounts(data)
        } catch {
            throw OpenCodexClientError.invalidResponse("OpenCodex returned an invalid Claude account response")
        }
    }
}

public actor OpenCodexPauseClient: OpenCodexPausing {
    private let transport: OpenCodexTransport

    public init(baseURL: URL, adminToken: String, timeout: TimeInterval, session: URLSession? = nil) {
        transport = OpenCodexTransport(
            baseURL: baseURL,
            adminToken: adminToken,
            timeout: timeout,
            session: session
        )
    }

    public func pauseAccount(id: String) async throws {
        let data = try await transport.send(
            path: "/api/codex-auth/accounts/pause",
            method: "PUT",
            operation: "pause",
            body: try JSONEncoder().encode(PauseRequest(id: id, paused: true))
        )
        guard let response = try? JSONDecoder().decode(PauseResponse.self, from: data),
              response.ok, response.id == id, response.paused else {
            throw OpenCodexClientError.invalidResponse("OpenCodex returned an invalid pause response")
        }
    }
}

public actor OpenCodexClient: OpenCodexServing {
    private let quotaClient: OpenCodexQuotaClient
    private let pauseClient: OpenCodexPauseClient

    public init(baseURL: URL, adminToken: String, timeout: TimeInterval, session: URLSession? = nil) {
        quotaClient = OpenCodexQuotaClient(
            baseURL: baseURL,
            adminToken: adminToken,
            timeout: timeout,
            session: session
        )
        pauseClient = OpenCodexPauseClient(
            baseURL: baseURL,
            adminToken: adminToken,
            timeout: timeout,
            session: session
        )
    }

    public func fetchAccounts() async throws -> [OpenCodexAccount] {
        try await quotaClient.fetchAccounts()
    }

    public func fetchClaudeAccounts() async throws -> [ClaudeAccount] {
        try await quotaClient.fetchClaudeAccounts()
    }

    public func pauseAccount(id: String) async throws {
        try await pauseClient.pauseAccount(id: id)
    }
}

private struct OpenCodexTransport: Sendable {
    private let baseURL: URL
    private let adminToken: String
    private let session: URLSession

    init(baseURL: URL, adminToken: String, timeout: TimeInterval, session: URLSession?) {
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

    func send(
        path: String,
        method: String,
        operation: String,
        body: Data? = nil
    ) async throws -> Data {
        var request = URLRequest(url: endpoint(path))
        request.httpMethod = method
        request.setValue("Bearer \(adminToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }
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

    private func endpoint(_ path: String) -> URL {
        URL(string: path, relativeTo: baseURL)!.absoluteURL
    }
}

public enum OpenCodexResponseDecoder {
    public static func decodeAccounts(_ data: Data) throws -> [OpenCodexAccount] {
        try JSONDecoder().decode(AccountsResponse.self, from: data).accounts.map { dto in
            OpenCodexAccount(
                id: dto.id,
                alias: dto.alias,
                plan: dto.plan,
                isMain: dto.isMain ?? false,
                paused: dto.paused,
                weeklyUsedPercent: dto.quota?.weeklyPercent
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
    let plan: String?
    let isMain: Bool?
    let paused: Bool
    let quota: QuotaDTO?
}
private struct QuotaDTO: Decodable {
    let fiveHourPercent: Double?
    let weeklyPercent: Double?
}
private struct ClaudeAccountsResponse: Decodable { let accounts: [ClaudeAccountDTO] }
private struct ClaudeAccountDTO: Decodable {
    let id: String
    let alias: String?
    let email: String?
    let quota: QuotaDTO?
}
private struct PauseRequest: Encodable { let id: String; let paused: Bool }
private struct PauseResponse: Decodable { let ok: Bool; let id: String; let paused: Bool }
