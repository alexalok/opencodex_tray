import Foundation

public enum CodexBaseline: String, CaseIterable, Sendable {
    case native, plus, proLite, pro, proMax

    public var label: String {
        switch self {
        case .native: "Each account (native)"
        case .plus: "Plus"
        case .proLite: "Pro $100 (10× Plus)"
        case .pro: "Pro $200 (20× Plus)"
        case .proMax: "Pro $500 (50× Plus)"
        }
    }

    private var capacity: Double {
        switch self {
        case .native, .plus: 1
        case .proLite: 10
        case .pro: 20
        case .proMax: 50
        }
    }

    private static func tier(for plan: String?) -> CodexBaseline? {
        switch plan?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "plus": .plus
        case "prolite": .proLite
        case "pro": .pro
        case "promax": .proMax
        default: nil
        }
    }

    public func factor(for plan: String?) -> Double? {
        if self == .native { return 1 }
        return Self.tier(for: plan).map { $0.capacity / capacity }
    }

    static func hasUncappedSession(plan: String?) -> Bool {
        switch tier(for: plan) {
        case .proLite, .pro, .proMax: true
        default: false
        }
    }
}

public enum ClaudeBaseline: String, CaseIterable, Sendable {
    case native, pro, max5x, ultra

    public var label: String {
        switch self {
        case .native: "Each account (native)"
        case .pro: "Pro"
        case .max5x: "Max (5× Pro)"
        case .ultra: "Ultra (10× Pro weekly)"
        }
    }

    private var weeklyCapacity: Double {
        switch self {
        case .native, .pro: 1
        case .max5x: 5
        case .ultra: 10
        }
    }

    public func factor(for plan: String?, weekly: Bool) -> Double? {
        if self == .native { return 1 }
        let tier: ClaudeBaseline
        switch plan?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "pro": tier = .pro
        case "max_5x": tier = .max5x
        case "max_20x": tier = .ultra
        default: return nil
        }
        // Ultra (formerly Max 20×) has no 5h cap once verified; temporary
        // unverified caps have no published ratio. Never infer verification.
        if !weekly && (tier == .ultra || self == .ultra) { return nil }
        return tier.weeklyCapacity / weeklyCapacity
    }
}

public struct SubscriptionSettings: Equatable, Sendable {
    public var codex: CodexBaseline
    public var claude: ClaudeBaseline

    public init(codex: CodexBaseline = .pro, claude: ClaudeBaseline = .native) {
        self.codex = codex
        self.claude = claude
    }
}

public struct SubscriptionSettingsStore {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> SubscriptionSettings {
        SubscriptionSettings(
            codex: defaults.string(forKey: "codexBaseline").flatMap(CodexBaseline.init(rawValue:)) ?? .pro,
            claude: defaults.string(forKey: "claudeBaseline").flatMap(ClaudeBaseline.init(rawValue:)) ?? .native
        )
    }

    public func save(_ settings: SubscriptionSettings) {
        defaults.set(settings.codex.rawValue, forKey: "codexBaseline")
        defaults.set(settings.claude.rawValue, forKey: "claudeBaseline")
    }
}
