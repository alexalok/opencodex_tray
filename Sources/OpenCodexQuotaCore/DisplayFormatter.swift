import Foundation

public enum DisplayFormatter {
    public static func trayTitle(_ percentage: Int?) -> String {
        percentage.map { "\($0)%" } ?? "—"
    }

    public static func row(_ allowance: AccountAllowance) -> String {
        let remaining = allowance.remainingPercent.map(format) ?? "—"
        let total = allowance.totalPercent.map(format) ?? "—"
        return "\(allowance.label): \(remaining)%/\(total)%"
    }

    public static func claudeTrayTitle(_ summary: ClaudeQuotaSummary) -> String {
        "\(percentage(summary.fiveHourRemainingPercentage))/\(percentage(summary.weeklyRemainingPercentage))"
    }

    public static func claudeRow(_ allowance: ClaudeAccountAllowance) -> String {
        "\(allowance.label): \(percentage(allowance.fiveHourRemainingPercent))/\(percentage(allowance.weeklyRemainingPercent))"
    }

    private static func percentage(_ value: Int?) -> String {
        value.map { "\($0)%" } ?? "—"
    }

    private static func percentage(_ value: Double?) -> String {
        value.map { "\(format($0))%" } ?? "—"
    }

    private static func format(_ value: Double) -> String {
        var result = String(format: "%.2f", value)
        while result.last == "0" { result.removeLast() }
        if result.last == "." { result.removeLast() }
        return result
    }
}
