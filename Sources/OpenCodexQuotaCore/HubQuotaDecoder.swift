import Foundation

public enum HubQuotaDecoder {
    public static func decode(_ data: Data) throws -> QuotaSnapshot {
        let response = try JSONDecoder().decode(Response.self, from: data)
        guard response.schemaVersion == 1, let generatedAt = date(response.generatedAt) else {
            throw ConfigurationError.invalid("Unsupported hub quota response; update hub and tray")
        }
        let codex = response.providers.openai
        let claude = response.providers.anthropic
        guard codex.accounts.count <= 200, claude.accounts.count <= 200 else {
            throw ConfigurationError.invalid("Hub quota response exceeds account limit")
        }
        let codexAccounts = try codex.accounts.map { row in
            try validate(row.weeklyPercent, row.autoSwitchThreshold)
            return OpenCodexAccount(id: row.id, alias: row.alias, plan: row.plan,
                isMain: row.isMain ?? false, paused: row.paused ?? false,
                weeklyUsedPercent: row.weeklyPercent,
                resetCreditExpirations: try row.resetCreditExpirations.map { values in
                    try values.map { value in
                        guard let date = date(value) else { throw ConfigurationError.invalid("Invalid hub reset date") }
                        return date
                    }
                }, autoSwitchThreshold: row.autoSwitchThreshold)
        }
        let claudeAccounts = try claude.accounts.map { row in
            try validate(row.fiveHourPercent, row.weeklyPercent)
            return ClaudeAccount(id: row.id, alias: row.alias, email: nil,
                fiveHourUsedPercent: row.fiveHourPercent, weeklyUsedPercent: row.weeklyPercent)
        }
        return QuotaSnapshot(codexEnabled: codex.enabled, claudeEnabled: claude.enabled,
            fetchedAt: generatedAt,
            codexSummary: !codex.enabled || codex.error == nil ? QuotaCalculator.summarize(accounts: codex.enabled ? codexAccounts : []) : nil,
            codexErrorMessage: codex.enabled && codex.error != nil ? "Hub Codex quota unavailable" : nil,
            claudeSummary: !claude.enabled || claude.error == nil ? ClaudeQuotaCalculator.summarize(accounts: claude.enabled ? claudeAccounts : []) : nil,
            claudeErrorMessage: claude.enabled && claude.error != nil ? "Hub Claude quota unavailable" : nil)
    }

    private static func validate(_ values: Double?...) throws {
        guard values.compactMap({ $0 }).allSatisfy({ $0.isFinite && (0...100).contains($0) }) else {
            throw ConfigurationError.invalid("Invalid hub quota percentage")
        }
    }
    private static func date(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
    private struct Response: Decodable {
        let schemaVersion: Int
        let generatedAt: String
        let providers: Providers
    }
    private struct Providers: Decodable { let openai: Provider; let anthropic: Provider }
    private struct Provider: Decodable {
        let enabled: Bool
        let accounts: [Account]
        let error: String?
    }
    private struct Account: Decodable {
        let id: String
        let alias: String?
        let plan: String?
        let isMain: Bool?
        let paused: Bool?
        let weeklyPercent: Double?
        let fiveHourPercent: Double?
        let autoSwitchThreshold: Double?
        let resetCreditExpirations: [String]?
    }
}
