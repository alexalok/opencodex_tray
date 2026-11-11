import Foundation

/// Formatting only: floors percentages and renders durations. Every value comes from OpenCodex.
public enum DisplayFormatter {
    public static func percent(_ value: Double) -> String {
        "\(Int(max(0, value).rounded(.down)))%"
    }

    /// `5h/weekly`, or the single known window when the other is absent.
    public static func usage(fiveHour: TrayQuotaWindow?, weekly: TrayQuotaWindow?) -> String? {
        switch (fiveHour, weekly) {
        case let (five?, week?): "\(percent(five.remainingPercent))/\(percent(week.remainingPercent))"
        case let (five?, nil): percent(five.remainingPercent)
        case let (nil, week?): percent(week.remainingPercent)
        case (nil, nil): nil
        }
    }

    /// `2d3h`, `1h30m`, `5m`; `spaced` separates days from hours (`2d 3h`).
    public static func duration(untilMilliseconds target: Double, now: Date, spaced: Bool = false) -> String {
        let minutes = max(0, Int(((target / 1_000 - now.timeIntervalSince1970) / 60).rounded(.up)))
        let days = minutes / 1_440, hours = minutes % 1_440 / 60, rest = minutes % 60
        if days > 0 { return spaced ? "\(days)d \(hours)h" : "\(days)d\(hours)h" }
        if hours > 0 { return "\(hours)h\(rest)m" }
        return "\(rest)m"
    }

    /// Up to the first space, at most 10 characters.
    public static func accountName(_ name: String) -> String {
        let word = name.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init) ?? name
        return String(word.prefix(10))
    }

    public static func units(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%g", value)
    }

    /// `name [plan xN] 30%/90%`.
    public static func accountRow(_ account: TrayQuotaAccount) -> String {
        var parts = [accountName(account.name)]
        if let plan = account.plan, !plan.isEmpty { parts.append("[\(plan) x\(units(account.units))]") }
        switch account.state {
        case "reauth": parts.append("reauth")
        case "paused": parts.append("paused")
        default: break
        }
        parts.append(usage(fiveHour: account.fiveHour, weekly: account.weekly) ?? "–")
        return parts.joined(separator: " ")
    }

    /// `x2, 2d3h` after the reset icon, or nil without reset credits.
    public static func resetCredits(_ account: TrayQuotaAccount, now: Date) -> String? {
        guard let credits = account.resetCredits, credits.count > 0 else { return nil }
        guard let expiry = credits.soonestExpiresAt else { return "x\(credits.count)" }
        return "x\(credits.count), \(duration(untilMilliseconds: expiry, now: now))"
    }

    /// One row per window with upcoming recoveries, one column per account, soonest first:
    /// `5h recovery: 1h30m (+30%) | 3h (+10%)` then `7d recovery: …`. No 5-hour window, no 5h row.
    public static func recoveries(_ provider: TrayQuotaProvider, now: Date) -> [String] {
        func row(_ label: String, _ window: TrayQuotaWindow?) -> String? {
            guard let window else { return nil }
            // An OpenCodex without per-account recoveries still reports the pool's next one.
            let entries = window.recoveries ?? window.nextRecoveryAt.flatMap { at in
                window.nextRecoveryPercent.map { [TrayQuotaRecovery(at: at, percent: $0)] }
            } ?? []
            guard !entries.isEmpty else { return nil }
            let columns = entries.map { "\(duration(untilMilliseconds: $0.at, now: now)) (+\(percent($0.percent)))" }
            return "\(label) recovery: \(columns.joined(separator: " | "))"
        }
        return [row("5h", provider.fiveHour), row("7d", provider.weekly)].compactMap { $0 }
    }

    public static func providerName(_ id: String) -> String {
        switch id {
        case "openai": "Codex"
        case "anthropic": "Claude"
        case "claude-cli": "Claude CLI"
        case "zai": "Z.ai"
        default: id
        }
    }

    public static func providerIcon(_ id: String) -> String? {
        switch id {
        case "openai": "ProviderIcon-codex"
        case "anthropic", "claude-cli": "ProviderIcon-claude"
        case "zai": "ProviderIcon-zai"
        default: nil
        }
    }

    /// Section title: provider name with its pooled remaining.
    public static func providerTitle(_ provider: TrayQuotaProvider) -> String {
        let name = providerName(provider.provider)
        if provider.blocked != nil { return "\(name) — exhausted" }
        return usage(fiveHour: provider.fiveHour, weekly: provider.weekly).map { "\(name) \($0)" } ?? name
    }
}
