import Foundation
import OpenCodexQuotaCore

enum QuotaWidgetContent: Equatable, Sendable {
    case snapshot(QuotaSnapshot, stale: Bool)
    case unavailable
}

struct QuotaWidgetResolution: Equatable, Sendable {
    let content: QuotaWidgetContent
    let snapshotToCache: QuotaSnapshot?
}

enum QuotaWidgetStateResolver {
    static func resolve(
        load: QuotaSnapshotLoad?,
        cached: QuotaSnapshot?
    ) -> QuotaWidgetResolution {
        guard let snapshot = load?.snapshot, snapshot.hasProviderData else {
            return QuotaWidgetResolution(
                content: cached.map { .snapshot($0, stale: true) } ?? .unavailable,
                snapshotToCache: nil
            )
        }

        return QuotaWidgetResolution(
            content: .snapshot(snapshot, stale: false),
            snapshotToCache: snapshot.isComplete ? snapshot : nil
        )
    }
}

struct QuotaWidgetRowModel: Equatable, Identifiable {
    let id: String
    let label: String
    let value: String
    let accessibilityLabel: String
}

struct QuotaWidgetProviderModel: Equatable {
    let total: String
    let rows: [QuotaWidgetRowModel]
    let overflowCount: Int
    let isUnavailable: Bool
    let accessibilityLabel: String
}

struct QuotaWidgetAge: Equatable {
    let display: String
    let accessibilityLabel: String
}

enum QuotaWidgetAgeText {
    static func make(updatedAt: Date?, relativeTo referenceDate: Date) -> QuotaWidgetAge? {
        guard let updatedAt else { return nil }

        let elapsed = max(0, referenceDate.timeIntervalSince(updatedAt))
        guard elapsed >= 60 else {
            return QuotaWidgetAge(display: "now", accessibilityLabel: "Updated now")
        }

        let value: Int
        let abbreviation: String
        let unit: String

        if elapsed < 60 * 60 {
            value = Int(elapsed / 60)
            abbreviation = "m"
            unit = "minute"
        } else if elapsed < 24 * 60 * 60 {
            value = Int(elapsed / (60 * 60))
            abbreviation = "h"
            unit = "hour"
        } else if elapsed < 7 * 24 * 60 * 60 {
            value = Int(elapsed / (24 * 60 * 60))
            abbreviation = "d"
            unit = "day"
        } else {
            value = Int(elapsed / (7 * 24 * 60 * 60))
            abbreviation = "w"
            unit = "week"
        }

        let spokenUnit = value == 1 ? unit : "\(unit)s"
        return QuotaWidgetAge(
            display: "\(value)\(abbreviation) ago",
            accessibilityLabel: "Updated \(value) \(spokenUnit) ago"
        )
    }
}

/// Spoken-form quota strings built from raw optional values so VoiceOver
/// always maps each number to its period, independent of display formatting.
private enum QuotaSpokenText {
    static func percent(_ value: Int?) -> String {
        value.map { "\($0) percent" } ?? "unknown"
    }

    static func percent(_ value: Double?) -> String {
        value.map { "\(trimmed($0)) percent" } ?? "unknown"
    }

    static func claudePeriods(fiveHour: String, weekly: String) -> String {
        "5-hour remaining: \(fiveHour); 1-week remaining: \(weekly)"
    }

    private static func trimmed(_ value: Double) -> String {
        var result = String(format: "%.2f", value)
        while result.last == "0" { result.removeLast() }
        if result.last == "." { result.removeLast() }
        return result
    }
}

struct QuotaWidgetViewModel: Equatable {
    let codex: QuotaWidgetProviderModel
    let claude: QuotaWidgetProviderModel
    let updatedAt: Date?
    let isStale: Bool
    let isUnavailable: Bool

    init(content: QuotaWidgetContent) {
        switch content {
        case .unavailable:
            codex = Self.unavailableProvider(named: "Codex")
            claude = Self.unavailableProvider(named: "Claude")
            updatedAt = nil
            isStale = false
            isUnavailable = true
        case let .snapshot(snapshot, stale):
            codex = snapshot.codexSummary.map(Self.codexProvider)
                ?? Self.unavailableProvider(named: "Codex")
            claude = snapshot.claudeSummary.map(Self.claudeProvider)
                ?? Self.unavailableProvider(named: "Claude")
            updatedAt = snapshot.fetchedAt
            isStale = stale
            isUnavailable = false
        }
    }

    private static func unavailableProvider(named name: String) -> QuotaWidgetProviderModel {
        QuotaWidgetProviderModel(
            total: "Unavailable",
            rows: [],
            overflowCount: 0,
            isUnavailable: true,
            accessibilityLabel: "\(name), unavailable"
        )
    }

    private static func codexProvider(_ summary: QuotaSummary) -> QuotaWidgetProviderModel {
        QuotaWidgetProviderModel(
            total: DisplayFormatter.trayTitle(summary.trayPercentage),
            rows: summary.rows.prefix(2).map {
                QuotaWidgetRowModel(
                    id: $0.id,
                    label: $0.label,
                    value: DisplayFormatter.codexAllowance($0),
                    accessibilityLabel: "Codex \($0.label), remaining: "
                        + QuotaSpokenText.percent($0.remainingPercent)
                        + " of "
                        + QuotaSpokenText.percent($0.totalPercent)
                )
            },
            overflowCount: max(summary.rows.count - 2, 0),
            isUnavailable: false,
            accessibilityLabel: "Codex, remaining: "
                + QuotaSpokenText.percent(summary.trayPercentage)
        )
    }

    private static func claudeProvider(
        _ summary: ClaudeQuotaSummary
    ) -> QuotaWidgetProviderModel {
        QuotaWidgetProviderModel(
            total: DisplayFormatter.claudeTrayTitle(summary),
            rows: summary.rows.prefix(2).map {
                QuotaWidgetRowModel(
                    id: $0.id,
                    label: $0.label,
                    value: DisplayFormatter.claudeAllowance($0),
                    accessibilityLabel: "Claude \($0.label), "
                        + QuotaSpokenText.claudePeriods(
                            fiveHour: QuotaSpokenText.percent($0.fiveHourRemainingPercent),
                            weekly: QuotaSpokenText.percent($0.weeklyRemainingPercent)
                        )
                )
            },
            overflowCount: max(summary.rows.count - 2, 0),
            isUnavailable: false,
            accessibilityLabel: "Claude, "
                + QuotaSpokenText.claudePeriods(
                    fiveHour: QuotaSpokenText.percent(summary.fiveHourRemainingPercentage),
                    weekly: QuotaSpokenText.percent(summary.weeklyRemainingPercentage)
                )
        )
    }
}
