import Foundation

public struct OpenCodexAccount: Equatable, Sendable {
    public let id: String
    public let alias: String?
    public let plan: String?
    public let isMain: Bool
    public let paused: Bool
    public let weeklyUsedPercent: Double?
    public let fiveHourUsedPercent: Double?
    /// True only when OpenCodex reported this account's quota without a five-hour window,
    /// meaning the plan has no five-hour limit. False when five-hour usage is merely unknown.
    public let fiveHourLimitAbsent: Bool
    public var resetCreditExpirations: [Date]?
    public let autoSwitchThreshold: Double?

    public init(
        id: String,
        alias: String?,
        plan: String?,
        isMain: Bool,
        paused: Bool = false,
        weeklyUsedPercent: Double?,
        fiveHourUsedPercent: Double? = nil,
        fiveHourLimitAbsent: Bool = false,
        resetCreditExpirations: [Date]? = nil,
        autoSwitchThreshold: Double? = nil
    ) {
        self.id = id
        self.alias = alias
        self.plan = plan
        self.isMain = isMain
        self.paused = paused
        self.weeklyUsedPercent = weeklyUsedPercent
        self.fiveHourUsedPercent = fiveHourUsedPercent
        self.fiveHourLimitAbsent = fiveHourLimitAbsent && fiveHourUsedPercent == nil
        self.resetCreditExpirations = resetCreditExpirations
        self.autoSwitchThreshold = autoSwitchThreshold
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

public struct AccountAllowance: Codable, Equatable, Sendable, Identifiable {
    public var id: String { accountId }
    public let accountId: String
    public let label: String
    public let paused: Bool
    public let remainingPercent: Double?
    public let totalPercent: Double?
    /// Pro-equivalent five-hour remaining allowance; nil when OpenCodex reports no short window.
    public let fiveHourRemainingPercent: Double?
    /// The account's plan has no five-hour limit, so only its weekly allowance gates it.
    public let fiveHourLimitAbsent: Bool
    public let resetCreditExpirations: [Date]?

    public init(
        accountId: String,
        label: String,
        paused: Bool = false,
        remainingPercent: Double?,
        totalPercent: Double?,
        fiveHourRemainingPercent: Double? = nil,
        fiveHourLimitAbsent: Bool = false,
        resetCreditExpirations: [Date]? = nil
    ) {
        self.accountId = accountId
        self.label = label
        self.paused = paused
        self.remainingPercent = remainingPercent
        self.totalPercent = totalPercent
        self.fiveHourRemainingPercent = fiveHourRemainingPercent
        self.fiveHourLimitAbsent = fiveHourLimitAbsent && fiveHourRemainingPercent == nil
        self.resetCreditExpirations = resetCreditExpirations
    }

    public func expiringReset(at now: Date) -> Date? {
        resetCreditExpirations?.filter {
            let remaining = $0.timeIntervalSince(now)
            return remaining > 0 && remaining < 7 * 24 * 60 * 60
        }.min()
    }

    private enum CodingKeys: String, CodingKey {
        case accountId, label, paused, remainingPercent, totalPercent, fiveHourRemainingPercent, fiveHourLimitAbsent
        case resetCreditExpirations
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        accountId = try values.decode(String.self, forKey: .accountId)
        label = try values.decode(String.self, forKey: .label)
        // Older widget snapshots predate pause-state display.
        paused = try values.decodeIfPresent(Bool.self, forKey: .paused) ?? false
        remainingPercent = try values.decodeIfPresent(Double.self, forKey: .remainingPercent)
        totalPercent = try values.decodeIfPresent(Double.self, forKey: .totalPercent)
        // Older widget snapshots predate five-hour tracking; absence keeps the provider visible.
        fiveHourRemainingPercent = try values.decodeIfPresent(Double.self, forKey: .fiveHourRemainingPercent)
        // Older snapshots cannot tell an absent five-hour limit from unknown usage; treat it as unknown.
        let decodedLimitAbsent = try values.decodeIfPresent(Bool.self, forKey: .fiveHourLimitAbsent) ?? false
        fiveHourLimitAbsent = fiveHourRemainingPercent == nil && decodedLimitAbsent
        resetCreditExpirations = try values.decodeIfPresent([Date].self, forKey: .resetCreditExpirations)
    }
}

public struct QuotaSummary: Codable, Equatable, Sendable {
    /// Weekly Pro-equivalent remaining allowance across unpaused accounts.
    public let trayPercentage: Int?
    public let rows: [AccountAllowance]

    public init(trayPercentage: Int?, rows: [AccountAllowance]) {
        self.trayPercentage = trayPercentage
        self.rows = rows
    }

    private var activeRows: [AccountAllowance] { rows.filter { !$0.paused } }

    /// An unpaused account without a five-hour limit that still has (or may have) weekly
    /// allowance is a fallback once every five-hour window is spent, so the pool has no
    /// five-hour ceiling. Accounts without a limit but with no weekly allowance left are skipped.
    public var fiveHourUnlimited: Bool {
        activeRows.contains { $0.fiveHourLimitAbsent && ($0.remainingPercent.map { $0 > 0 } ?? true) }
    }

    private var fiveHourWindows: [Double?] {
        activeRows.filter { !$0.fiveHourLimitAbsent }.map(\.fiveHourRemainingPercent)
    }

    /// Five-hour Pro-equivalent remaining allowance; nil when unlimited or unknown.
    public var fiveHourPercentage: Int? {
        guard !fiveHourUnlimited, fiveHourWindows.allSatisfy({ $0 != nil }) else { return nil }
        return floorStable(fiveHourWindows.reduce(0) { $0 + ($1 ?? 0) })
    }

    /// True when the five-hour pool is unlimited or its unrounded total exceeds the tray
    /// threshold, and the unrounded weekly total of unpaused accounts exceeds it too.
    public var hideFromTray: Bool {
        (fiveHourUnlimited || exceedsTrayThreshold(fiveHourWindows))
            && exceedsTrayThreshold(activeRows.map(\.remainingPercent))
    }
}

public struct ClaudeAccountAllowance: Codable, Equatable, Sendable, Identifiable {
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

public struct ClaudeQuotaSummary: Codable, Equatable, Sendable {
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

    /// True when every account reports both windows and the unrounded five-hour
    /// and weekly pool totals each exceed the tray threshold.
    public var hideFromTray: Bool {
        exceedsTrayThreshold(rows.map(\.fiveHourRemainingPercent))
            && exceedsTrayThreshold(rows.map(\.weeklyRemainingPercent))
    }
}

public enum QuotaCalculator {
    public static func summarize(accounts: [OpenCodexAccount]) -> QuotaSummary {
        let rows = accounts.map { account in
            let factor = proEquivalentFactor(plan: account.plan)
            // Zero disables auto-switching; absent thresholds preserve full allowance.
            let threshold = account.autoSwitchThreshold ?? 100
            let nativeTotal = threshold > 0 && threshold <= 100 ? threshold : 100
            let total = factor.map { nativeTotal * $0 }
            func remaining(_ used: Double?) -> Double? {
                used.flatMap { used in factor.map { max(nativeTotal - max(used, 0), 0) * $0 } }
            }
            let label = account.alias ?? (account.isMain ? "main" : account.id)
            return AccountAllowance(
                accountId: account.id,
                label: label,
                paused: account.paused,
                remainingPercent: remaining(account.weeklyUsedPercent),
                totalPercent: total,
                fiveHourRemainingPercent: remaining(account.fiveHourUsedPercent),
                fiveHourLimitAbsent: account.fiveHourLimitAbsent,
                resetCreditExpirations: account.resetCreditExpirations
            )
        }

        let activeRows = rows.filter { !$0.paused }
        guard activeRows.allSatisfy({ $0.remainingPercent != nil && $0.totalPercent != nil }) else {
            return QuotaSummary(trayPercentage: nil, rows: rows)
        }
        let percentage = floorStable(activeRows.reduce(0) { $0 + ($1.remainingPercent ?? 0) })
        return QuotaSummary(trayPercentage: percentage, rows: rows)
    }

    private static func proEquivalentFactor(plan: String?) -> Double? {
        switch plan?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "pro": 1
        case "prolite": 0.25
        case "plus": 0.05
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

public enum TrayVisibility {
    /// Hide a provider from the menu bar only when its unrounded pool totals are known and
    /// strictly above this value. Any missing or non-finite value keeps the provider visible.
    public static let hideThresholdPercent: Double = 95
}

private func exceedsTrayThreshold(_ values: [Double?]) -> Bool {
    guard !values.isEmpty, values.allSatisfy({ $0?.isFinite == true }) else { return false }
    return values.reduce(0) { $0 + ($1 ?? 0) } > TrayVisibility.hideThresholdPercent
}
