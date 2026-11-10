import Foundation

public protocol QuotaHTTPServing: Sendable {
    func get(_ url: URL, headers: [String: String]) async throws -> Data
}

/// Credentials must never follow a redirect, even to another HTTPS origin.
final class QuotaRedirectDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

public final class QuotaHTTPClient: QuotaHTTPServing {
    private let session: URLSession
    public init(timeout: TimeInterval) {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout
        config.httpShouldSetCookies = false
        config.urlCredentialStorage = nil
        session = URLSession(configuration: config, delegate: QuotaRedirectDelegate(), delegateQueue: nil)
    }
    deinit { session.invalidateAndCancel() }

    public func get(_ url: URL, headers: [String: String]) async throws -> Data {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.httpMethod = "GET"
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        let (bytes, response) = try await session.bytes(for: request)
        defer { bytes.task.cancel() }
        guard let response = response as? HTTPURLResponse else { throw ConfigurationError.invalid("Invalid quota HTTP response") }
        guard response.statusCode == 200 else {
            var body = Data()
            if response.statusCode == 403 {
                for try await byte in bytes {
                    guard body.count < Self.errorBodyLimit else { break }
                    body.append(byte)
                }
            }
            throw ConfigurationError.invalid(Self.failureMessage(status: response.statusCode, body: body))
        }
        guard response.expectedContentLength <= 1_048_576 else { throw ConfigurationError.invalid("Quota response exceeds size limit") }
        var data = Data()
        for try await byte in bytes {
            guard data.count < 1_048_576 else { throw ConfigurationError.invalid("Quota response exceeds size limit") }
            data.append(byte)
        }
        return data
    }

    static let errorBodyLimit = 4_096
    static let missingEndpointMessage = "OpenCodex lacks the tray endpoint; update OpenCodex (and the Link Home)"

    /// An older OpenCodex has no tray read: the route is unknown (404), or a Link relay that does not
    /// list it refuses it as a write (403 `link_child_read_only`). Neither is a credential problem.
    static func failureMessage(status: Int, body: Data) -> String {
        switch status {
        case 401: return "Quota credential rejected; reconnect OpenCodex"
        case 403:
            struct Refusal: Decodable { let code: String? }
            let code = (try? JSONDecoder().decode(Refusal.self, from: body))?.code
            return code == "link_child_read_only" ? missingEndpointMessage : "OpenCodex refused the quota read (HTTP 403)"
        case 404: return missingEndpointMessage
        case 300...399: return "Quota redirects are refused; configure the final source URL"
        default: return "Quota source unavailable (HTTP \(status))"
        }
    }
}
