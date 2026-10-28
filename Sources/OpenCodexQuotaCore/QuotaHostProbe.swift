import Foundation

struct QuotaHostProbe: Sendable {
    let http: any QuotaHTTPServing

    func role(at host: URL) async throws -> String {
        let health = try JSONDecoder().decode(Health.self, from: await http.get(host.appendingPathComponent("healthz"), headers: [:]))
        guard health.service == "opencodex" else { throw ConfigurationError.invalid("Configured host is not OpenCodex") }
        // Standalone/hub listeners before v2.89 omit role; the client listener always includes it.
        return health.role ?? "local"
    }

    func validate(_ connection: QuotaConnection) async throws {
        let role = try await role(at: connection.hostURL)
        if connection.mode == .local {
            guard ["local", "standalone", "hub"].contains(role) else {
                throw ConfigurationError.invalid("Host switched to client mode; refresh tray connection")
            }
            return
        }
        guard role == "client", QuotaConnection.isLoopback(connection.hostURL) else {
            throw ConfigurationError.invalid("Hub enrollment must be verified through the local OpenCodex listener")
        }
        let html = try await http.get(connection.hostURL.appendingPathComponent("opencodex-session"), headers: [:])
        let bootstrap = try Self.bootstrap(html, host: connection.hostURL)
        let status = try JSONDecoder().decode(MachineStatus.self, from: await http.get(
            connection.hostURL.appendingPathComponent("api/machine/status"),
            headers: ["x-opencodex-api-key": bootstrap.token, "x-opencodex-gui-origin": bootstrap.origin, "Origin": bootstrap.origin]))
        guard status.mode == "client", status.connected, status.managementTransport == "direct",
              status.apiKeyId == connection.apiKeyId, status.connectedAt == connection.connectedAt,
              let origin = URL(string: status.sharedServerOrigin),
              Self.sameOrigin(origin, connection.managementURL ?? connection.sourceURL) else {
            throw ConfigurationError.invalid("Host hub enrollment changed; refresh tray connection")
        }
    }

    static func bootstrap(_ data: Data, host: URL) throws -> (token: String, origin: String) {
        let html = String(decoding: data, as: UTF8.self)
        func meta(_ name: String) -> String? {
            let prefix = "<meta name=\"opencodex-session-\(name)\" content=\""
            guard let start = html.range(of: prefix)?.upperBound,
                  let end = html[start...].firstIndex(of: "\"") else { return nil }
            return String(html[start..<end]).replacingOccurrences(of: "&amp;", with: "&")
        }
        guard let token = meta("token"), !token.isEmpty,
              let origin = meta("origin"), let originURL = URL(string: origin), sameOrigin(originURL, host),
              let server = meta("server-origin"), let serverURL = URL(string: server), sameOrigin(serverURL, host) else {
            throw ConfigurationError.invalid("Local OpenCodex session unavailable; open host dashboard")
        }
        return (token, origin)
    }
    private static func sameOrigin(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.scheme == rhs.scheme && lhs.host == rhs.host && (lhs.port ?? (lhs.scheme == "https" ? 443 : 80)) == (rhs.port ?? (rhs.scheme == "https" ? 443 : 80))
    }
    private struct Health: Decodable { let service: String; let role: String? }
    private struct MachineStatus: Decodable {
        let mode: String
        let connected: Bool
        let managementTransport: String
        let sharedServerOrigin: String
        let apiKeyId: String
        let connectedAt: String
    }
}
