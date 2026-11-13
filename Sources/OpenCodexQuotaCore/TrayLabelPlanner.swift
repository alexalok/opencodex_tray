import Foundation

/// One provider in the menu-bar label.
public struct TrayLabelItem: Equatable, Sendable {
    public let provider: String
    public let text: String
    public let showsResetIcon: Bool

    public init(provider: String, text: String, showsResetIcon: Bool = false) {
        self.provider = provider
        self.text = text
        self.showsResetIcon = showsResetIcon
    }
}

/// Decides which providers the menu-bar label shows, from one quota read per minute.
///
/// - A provider whose every window is above `hideAbovePercent` remaining is never shown.
/// - Otherwise its floored `5h/weekly` remaining is shown for `showDuration` whenever it differs
///   from the value last shown, including the first read below the threshold.
/// - A blocked provider (no account can run) stays shown as `0%/0%` with the time until it
///   recovers, plus the reset icon when the weekly window holds it and reset credits exist.
public struct TrayLabelPlanner: Sendable {
    public static let hideAbovePercent: Double = 95
    /// Ten minutes, less slack for the once-a-minute tick arriving early.
    public static let showDuration: TimeInterval = 10 * 60 - 5

    private var lastShown: [String: String] = [:]
    private var shownUntil: [String: Date] = [:]

    public init() {}

    public mutating func update(_ quota: TrayQuota?, now: Date) -> [TrayLabelItem] {
        guard let quota else { return [] }
        var items: [TrayLabelItem] = []
        var seen = Set<String>()
        for provider in quota.providers {
            seen.insert(provider.provider)
            if let block = provider.blocked {
                lastShown[provider.provider] = nil
                shownUntil[provider.provider] = nil
                let zero = provider.fiveHour == nil ? "0%" : "0%/0%"
                let text = block.recoversAt.map { "\(zero) \(DisplayFormatter.duration(untilMilliseconds: $0, now: now, spaced: true))" } ?? zero
                items.append(TrayLabelItem(provider: provider.provider, text: text,
                    showsResetIcon: block.window == "weekly" && provider.resetCredits > 0))
                continue
            }
            let windows = [provider.fiveHour, provider.weekly].compactMap { $0 }
            guard !windows.isEmpty, !windows.allSatisfy({ $0.remainingPercent > Self.hideAbovePercent }),
                  let text = DisplayFormatter.usage(fiveHour: provider.fiveHour, weekly: provider.weekly) else {
                lastShown[provider.provider] = nil
                shownUntil[provider.provider] = nil
                continue
            }
            if lastShown[provider.provider] != text {
                lastShown[provider.provider] = text
                shownUntil[provider.provider] = now.addingTimeInterval(Self.showDuration)
            }
            if let until = shownUntil[provider.provider], now < until {
                items.append(TrayLabelItem(provider: provider.provider, text: text))
            }
        }
        for gone in Set(lastShown.keys).subtracting(seen) {
            lastShown[gone] = nil
            shownUntil[gone] = nil
        }
        return items
    }
}

/// The tray advances on a one-minute tick so label expiry and countdowns never wait on a read;
/// a slower configured poll interval only skips the read on the ticks in between.
public struct TrayTickSchedule: Sendable {
    public static let tick: TimeInterval = 60
    public let ticksPerRead: Int
    private var ticksSinceRead: Int?

    public init(pollInterval: TimeInterval) {
        ticksPerRead = max(1, Int((pollInterval / Self.tick).rounded(.up)))
    }

    /// Advances one tick and tells whether it reads; the first tick always does.
    public mutating func next() -> Bool {
        if let elapsed = ticksSinceRead, elapsed + 1 < ticksPerRead {
            ticksSinceRead = elapsed + 1
            return false
        }
        ticksSinceRead = 0
        return true
    }
}
