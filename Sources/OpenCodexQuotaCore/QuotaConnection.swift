import CryptoKit
import Foundation

/// A resolved connection contains exactly one credential, bound to its destination.
public struct QuotaConnection: Codable, Equatable, Sendable {
    public enum Mode: String, Codable, Sendable { case local, hub }
    public let mode: Mode
    public let hostURL: URL
    public let sourceURL: URL
    public let token: String
    public let apiKeyId: String?
    public let connectedAt: String?
    public let managementURL: URL?
    public let codexEnabled: Bool
    public let claudeEnabled: Bool

    public var label: String { mode == .hub ? "Hub: \(sourceURL.host ?? "unknown")" : "Local OpenCodex" }
    public var sourceID: String {
        // Hash the credential so rotation also invalidates cached snapshots without exposing it.
        let identity = [mode.rawValue, hostURL.absoluteString, sourceURL.absoluteString, apiKeyId ?? "", connectedAt ?? "", String(codexEnabled), String(claudeEnabled), token].joined(separator: "\n")
        return Self.fingerprint(identity)
    }

    public static func resolve(hostURL: URL, runningRole: String, configData: Data?, adminToken: String?, dataToken: String?) throws -> Self {
        let config = try JSONDecoder().decode(HostConfiguration.self, from: configData ?? Data("{}".utf8))
        let configuredRole = config.runtimeRole ?? "standalone"
        let runningRole = runningRole == "local" && configuredRole != "client" ? configuredRole : runningRole
        guard ["standalone", "hub", "client"].contains(runningRole), configuredRole == runningRole else {
            throw ConfigurationError.invalid("OpenCodex running mode differs from saved config; restart host service")
        }
        if runningRole != "client" {
            guard let adminToken, !adminToken.isEmpty else { throw ConfigurationError.invalid("Local OpenCodex admin token is unavailable") }
            return Self(mode: .local, hostURL: hostURL, sourceURL: hostURL, token: adminToken,
                        apiKeyId: nil, connectedAt: nil, managementURL: nil,
                        codexEnabled: config.providers == nil || (config.providers?["openai"] != nil && config.providers?["openai"]?.disabled != true),
                        claudeEnabled: config.providers == nil || (config.providers?["anthropic"] != nil && config.providers?["anthropic"]?.disabled != true))
        }
        guard let client = config.client, let dataToken, !dataToken.isEmpty,
              Self.fingerprint(dataToken) == client.tokenFingerprint,
              !client.apiKeyId.isEmpty, !client.connectedAt.isEmpty else {
            throw ConfigurationError.invalid("Hub credential does not match host enrollment; reconnect OpenCodex")
        }
        guard client.managementTransport == nil || client.managementTransport == "direct" else {
            throw ConfigurationError.invalid("Hub quota requires direct transport; Link transport is not supported")
        }
        let target = try validatedOrigin(client.serverUrl)
        let management = try validatedOrigin(client.managementUrl ?? client.serverUrl)
        return Self(mode: .hub, hostURL: hostURL, sourceURL: target, token: dataToken,
                    apiKeyId: client.apiKeyId, connectedAt: client.connectedAt, managementURL: management,
                    codexEnabled: true, claudeEnabled: true)
    }

    static func validatedOrigin(_ raw: String) throws -> URL {
        guard let url = URL(string: raw), let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              url.path.isEmpty || url.path == "/",
              url.scheme == "https" || (url.scheme == "http" && isLoopback(url)) else {
            throw ConfigurationError.invalid("Quota source must be an HTTPS origin (HTTP allowed only on loopback)")
        }
        return url
    }

    static func isLoopback(_ url: URL) -> Bool {
        let host = url.host ?? ""
        if ["localhost", "::1", "[::1]"].contains(host) { return true }
        let pieces = host.split(separator: ".", omittingEmptySubsequences: false)
        return pieces.count == 4 && pieces.first == "127" && pieces.allSatisfy { Int($0).map { (0...255).contains($0) } == true }
    }

    private static func fingerprint(_ token: String) -> String {
        SHA256.hash(data: Data(token.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

private struct HostConfiguration: Decodable {
    let runtimeRole: String?
    let client: ClientConfiguration?
    let providers: [String: ProviderConfiguration]?
}
private struct ProviderConfiguration: Decodable { let disabled: Bool? }
private struct ClientConfiguration: Decodable {
    let serverUrl: String
    let managementUrl: String?
    let managementTransport: String?
    let apiKeyId: String
    let connectedAt: String
    let tokenFingerprint: String
}
