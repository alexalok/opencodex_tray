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
            let message: String
            switch response.statusCode {
            case 401: message = "Quota credential rejected; reconnect OpenCodex"
            case 403: message = "Hub quota access not granted; enable allowQuotaRead for this client key"
            case 404: message = "Quota endpoint unavailable; update OpenCodex hub"
            case 300...399: message = "Quota redirects are refused; configure the final source URL"
            default: message = "Quota source unavailable (HTTP \(response.statusCode))"
            }
            throw ConfigurationError.invalid(message)
        }
        guard response.expectedContentLength <= 1_048_576 else { throw ConfigurationError.invalid("Quota response exceeds size limit") }
        var data = Data()
        for try await byte in bytes {
            guard data.count < 1_048_576 else { throw ConfigurationError.invalid("Quota response exceeds size limit") }
            data.append(byte)
        }
        return data
    }
}
