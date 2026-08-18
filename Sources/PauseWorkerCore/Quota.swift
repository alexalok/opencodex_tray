import Foundation

public struct OpenCodexAccount: Equatable, Sendable {
    public let id: String
    public let alias: String?
    public let plan: String?
    public let isMain: Bool
    public let paused: Bool
    public let weeklyUsedPercent: Double?

    public init(
        id: String,
        alias: String?,
        plan: String?,
        isMain: Bool,
        paused: Bool,
        weeklyUsedPercent: Double?
    ) {
        self.id = id
        self.alias = alias
        self.plan = plan
        self.isMain = isMain
        self.paused = paused
        self.weeklyUsedPercent = weeklyUsedPercent
    }
}

public struct ClaudeAccount: Equatable, Sendable {
    public let id: String
    public let alias: String?
    public let email: String?
    public let fiveHourUsedPercent: Double?
    public let weeklyUsedPercent: Double?

    public init(
        id: String,
        alias: String?,
        email: String?,
        fiveHourUsedPercent: Double? = nil,
        weeklyUsedPercent: Double?
    ) {
        self.id = id
        self.alias = alias
        self.email = email
        self.fiveHourUsedPercent = fiveHourUsedPercent
        self.weeklyUsedPercent = weeklyUsedPercent
    }
}

public struct AccountAllowance: Equatable, Sendable, Identifiable {
    public var id: String { accountId }
    public let accountId: String
    public let label: String
    public let remainingPercent: Double?
    public let totalPercent: Double?

    public init(accountId: String, label: String, remainingPercent: Double?, totalPercent: Double?) {
        self.accountId = accountId
        self.label = label
        self.remainingPercent = remainingPercent
        self.totalPercent = totalPercent
    }
}

public struct QuotaSummary: Equatable, Sendable {
    public let trayPercentage: Int?
    public let rows: [AccountAllowance]
}

public struct ClaudeAccountUsage: Equatable, Sendable, Identifiable {
    public var id: String { accountId }
    public let accountId: String
    public let label: String
    public let fiveHourUsedPercent: Double?
    public let weeklyUsedPercent: Double?

    public init(
        accountId: String,
        label: String,
        fiveHourUsedPercent: Double?,
        weeklyUsedPercent: Double?
    ) {
        self.accountId = accountId
        self.label = label
        self.fiveHourUsedPercent = fiveHourUsedPercent
        self.weeklyUsedPercent = weeklyUsedPercent
    }
}

public struct ClaudeQuotaSummary: Equatable, Sendable {
    public let fiveHourUsedPercentage: Int?
    public let weeklyUsedPercentage: Int?
    public let rows: [ClaudeAccountUsage]

    public init(
        fiveHourUsedPercentage: Int?,
        weeklyUsedPercentage: Int?,
        rows: [ClaudeAccountUsage]
    ) {
        self.fiveHourUsedPercentage = fiveHourUsedPercentage
        self.weeklyUsedPercentage = weeklyUsedPercentage
        self.rows = rows
    }
}

public enum QuotaError: Error, Equatable, LocalizedError, Sendable {
    case targetAliasNotFound(String)
    case duplicateTargetAlias(String)

    public var errorDescription: String? {
        switch self {
        case let .targetAliasNotFound(alias):
            "Target account alias \"\(alias)\" was not returned by OpenCodex"
        case let .duplicateTargetAlias(alias):
            "Target account alias \"\(alias)\" matched multiple OpenCodex accounts"
        }
    }
}

public enum QuotaCalculator {
    public static func summarize(
        accounts: [OpenCodexAccount],
        targetAlias: String,
        thresholdPercent: Double
    ) throws -> QuotaSummary {
        let targetMatches = accounts.filter { $0.alias == targetAlias }
        if targetMatches.isEmpty { throw QuotaError.targetAliasNotFound(targetAlias) }
        if targetMatches.count > 1 { throw QuotaError.duplicateTargetAlias(targetAlias) }

        let rows = accounts.map { account in
            let nativeTotal = account.alias == targetAlias ? thresholdPercent : 100
            let factor = proEquivalentFactor(plan: account.plan)
            let total = factor.map { nativeTotal * $0 }
            let remaining = account.weeklyUsedPercent.flatMap { used in
                factor.map { max(nativeTotal - max(used, 0), 0) * $0 }
            }
            let label = account.alias ?? (account.isMain ? "main" : account.id)
            return AccountAllowance(
                accountId: account.id,
                label: label,
                remainingPercent: remaining,
                totalPercent: total
            )
        }

        guard rows.allSatisfy({ $0.remainingPercent != nil && $0.totalPercent != nil }) else {
            return QuotaSummary(trayPercentage: nil, rows: rows)
        }
        let percentage = floorStable(rows.reduce(0) { $0 + ($1.remainingPercent ?? 0) })
        return QuotaSummary(trayPercentage: percentage, rows: rows)
    }

    private static func proEquivalentFactor(plan: String?) -> Double? {
        switch plan?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "pro": 1
        case "prolite": 0.25
        default: nil
        }
    }
}

public enum ClaudeQuotaCalculator {
    public static func summarize(accounts: [ClaudeAccount]) -> ClaudeQuotaSummary {
        let rows = accounts.map { account in
            ClaudeAccountUsage(
                accountId: account.id,
                label: account.alias ?? account.email ?? account.id,
                fiveHourUsedPercent: account.fiveHourUsedPercent,
                weeklyUsedPercent: account.weeklyUsedPercent
            )
        }
        return ClaudeQuotaSummary(
            fiveHourUsedPercentage: aggregate(rows.map(\.fiveHourUsedPercent)),
            weeklyUsedPercentage: aggregate(rows.map(\.weeklyUsedPercent)),
            rows: rows
        )
    }

    private static func aggregate(_ values: [Double?]) -> Int? {
        guard values.allSatisfy({ $0 != nil }) else { return nil }
        return floorStable(values.reduce(0) { $0 + ($1 ?? 0) })
    }
}

private func floorStable(_ value: Double) -> Int {
    let nearestInteger = value.rounded()
    let stabilized = abs(value - nearestInteger) < 1e-9 ? nearestInteger : value
    return Int(floor(stabilized))
}
