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

public struct ClaudeAccountAllowance: Equatable, Sendable, Identifiable {
    public var id: String { accountId }
    public let accountId: String
    public let label: String
    public let fiveHourRemainingPercent: Double?
    public let weeklyRemainingPercent: Double?

    public init(
        accountId: String,
        label: String,
        fiveHourRemainingPercent: Double?,
        weeklyRemainingPercent: Double?
    ) {
        self.accountId = accountId
        self.label = label
        self.fiveHourRemainingPercent = fiveHourRemainingPercent
        self.weeklyRemainingPercent = weeklyRemainingPercent
    }
}

public struct ClaudeQuotaSummary: Equatable, Sendable {
    public let fiveHourRemainingPercentage: Int?
    public let weeklyRemainingPercentage: Int?
    public let rows: [ClaudeAccountAllowance]

    public init(
        fiveHourRemainingPercentage: Int?,
        weeklyRemainingPercentage: Int?,
        rows: [ClaudeAccountAllowance]
    ) {
        self.fiveHourRemainingPercentage = fiveHourRemainingPercentage
        self.weeklyRemainingPercentage = weeklyRemainingPercentage
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
            ClaudeAccountAllowance(
                accountId: account.id,
                label: account.alias ?? account.email ?? account.id,
                fiveHourRemainingPercent: account.fiveHourUsedPercent.map { max(100 - max($0, 0), 0) },
                weeklyRemainingPercent: account.weeklyUsedPercent.map { max(100 - max($0, 0), 0) }
            )
        }
        return ClaudeQuotaSummary(
            fiveHourRemainingPercentage: aggregate(rows.map(\.fiveHourRemainingPercent)),
            weeklyRemainingPercentage: aggregate(rows.map(\.weeklyRemainingPercent)),
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
