import Foundation

public protocol OpenCodexServing: Sendable {
    func fetchAccounts() async throws -> [OpenCodexAccount]
    func fetchClaudeAccounts() async throws -> [ClaudeAccount]
    func pauseAccount(id: String) async throws
}

public actor OpenCodexClient: OpenCodexServing {
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
        do {
            return try OpenCodexResponseDecoder.decodeAccounts(data)
        } catch {
            throw OpenCodexClientError.invalidResponse("OpenCodex returned an invalid account response")
        }
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

    public func pauseAccount(id: String) async throws {
        var request = URLRequest(url: endpoint("/api/codex-auth/accounts/pause"))
        request.httpMethod = "PUT"
        request.setValue("Bearer \(adminToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(PauseRequest(id: id, paused: true))
        let data = try await send(request, operation: "pause")
        guard let response = try? JSONDecoder().decode(PauseResponse.self, from: data),
              response.ok, response.id == id, response.paused else {
            throw OpenCodexClientError.invalidResponse("OpenCodex returned an invalid pause response")
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
