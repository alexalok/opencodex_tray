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

    private static func format(_ value: Double) -> String {
        var result = String(format: "%.2f", value)
        while result.last == "0" { result.removeLast() }
        if result.last == "." { result.removeLast() }
        return result
    }
}
