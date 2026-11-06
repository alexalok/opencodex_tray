import Foundation

/// Decodes OpenCodex reports, never vendor credentials or vendor API payloads.
public enum ZaiQuotaDecoder {
    public static func decode(_ data: Data) throws -> ClaudeQuotaSummary {
        let response = try JSONDecoder().decode(Response.self, from: data)
        let reports = response.reports.filter { $0.source == "zai:quota-limit" }
        guard reports.count <= 200, Set(reports.map(\.provider)).count == reports.count else {
            throw ConfigurationError.invalid("Invalid Z.ai provider roster")
        }
        return ClaudeQuotaCalculator.summarize(accounts: try reports.map { report in
            guard !report.provider.isEmpty else { throw ConfigurationError.invalid("Invalid Z.ai provider") }
            let quota = report.quota
            guard [quota?.fiveHourPercent, quota?.weeklyPercent].compactMap({ $0 })
                .allSatisfy({ $0.isFinite && (0...100).contains($0) }) else {
                throw ConfigurationError.invalid("Invalid Z.ai quota percentage")
            }
            return ClaudeAccount(id: report.provider, alias: report.label ?? report.provider, email: nil,
                fiveHourUsedPercent: quota?.fiveHourPercent, weeklyUsedPercent: quota?.weeklyPercent)
        })
    }
    private struct Response: Decodable { let reports: [Report] }
    private struct Quota: Decodable { let fiveHourPercent: Double?; let weeklyPercent: Double? }
    private struct Report: Decodable {
        let provider: String
        let source: String
        let label: String?
        let quota: Quota?
        enum CodingKeys: String, CodingKey { case provider, source, label, quota }
        init(from decoder: any Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            source = try values.decode(String.self, forKey: .source)
            if source == "zai:quota-limit" {
                provider = try values.decode(String.self, forKey: .provider)
                label = try values.decodeIfPresent(String.self, forKey: .label)
                quota = try values.decodeIfPresent(Quota.self, forKey: .quota)
            } else { provider = ""; label = nil; quota = nil }
        }
    }
}
