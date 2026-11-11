import Foundation

/// `ocx.quota-tray/1` from `GET /api/quota-pool/tray`. OpenCodex computes every number here;
/// the tray only floors percentages and formats durations.
public struct TrayQuota: Decodable, Equatable, Sendable {
    public static let schema = "ocx.quota-tray/1"

    public let generatedAt: Double
    public let providers: [TrayQuotaProvider]

    public init(generatedAt: Double, providers: [TrayQuotaProvider]) {
        self.generatedAt = generatedAt
        self.providers = providers
    }

    private enum CodingKeys: String, CodingKey { case schema, generatedAt, providers }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decode(String.self, forKey: .schema) == Self.schema else {
            throw ConfigurationError.invalid("Unsupported quota format; update OpenCodex")
        }
        generatedAt = try container.decode(Double.self, forKey: .generatedAt)
        providers = try container.decode([TrayQuotaProvider].self, forKey: .providers)
    }

    public static func decode(_ data: Data) throws -> TrayQuota {
        do {
            return try JSONDecoder().decode(TrayQuota.self, from: data)
        } catch let error as ConfigurationError {
            throw error
        } catch {
            throw ConfigurationError.invalid("Quota response is invalid; update OpenCodex")
        }
    }
}

/// One account's upcoming reset in a pooled window and the share of the pool it returns.
public struct TrayQuotaRecovery: Decodable, Equatable, Sendable {
    public let at: Double
    public let percent: Double

    public init(at: Double, percent: Double) {
        self.at = at
        self.percent = percent
    }
}

/// Times are epoch milliseconds, as OpenCodex sends them.
public struct TrayQuotaWindow: Decodable, Equatable, Sendable {
    public let remainingPercent: Double
    public let resetsAt: Double?
    public let exhausted: Bool?
    public let nextRecoveryAt: Double?
    public let nextRecoveryPercent: Double?
    /// Every upcoming recovery, soonest first, one per account (OpenCodex with per-account recoveries).
    public let recoveries: [TrayQuotaRecovery]?

    public init(remainingPercent: Double, resetsAt: Double? = nil, exhausted: Bool? = nil,
                nextRecoveryAt: Double? = nil, nextRecoveryPercent: Double? = nil,
                recoveries: [TrayQuotaRecovery]? = nil) {
        self.remainingPercent = remainingPercent
        self.resetsAt = resetsAt
        self.exhausted = exhausted
        self.nextRecoveryAt = nextRecoveryAt
        self.nextRecoveryPercent = nextRecoveryPercent
        self.recoveries = recoveries
    }
}

public struct TrayQuotaBlock: Decodable, Equatable, Sendable {
    /// `5h`, `weekly` or `other`: the window whose reset is the first recovery.
    public let window: String
    public let recoversAt: Double?

    public init(window: String, recoversAt: Double? = nil) {
        self.window = window
        self.recoversAt = recoversAt
    }
}

public struct TrayQuotaResetCredits: Decodable, Equatable, Sendable {
    public let count: Int
    public let soonestExpiresAt: Double?

    public init(count: Int, soonestExpiresAt: Double? = nil) {
        self.count = count
        self.soonestExpiresAt = soonestExpiresAt
    }
}

public struct TrayQuotaAccount: Decodable, Equatable, Sendable {
    public let name: String
    public let plan: String?
    /// Plan capacity in Plus units.
    public let units: Double
    public let state: String
    public let fiveHour: TrayQuotaWindow?
    public let weekly: TrayQuotaWindow?
    public let resetCredits: TrayQuotaResetCredits?

    public init(name: String, plan: String? = nil, units: Double = 1, state: String = "available",
                fiveHour: TrayQuotaWindow? = nil, weekly: TrayQuotaWindow? = nil,
                resetCredits: TrayQuotaResetCredits? = nil) {
        self.name = name
        self.plan = plan
        self.units = units
        self.state = state
        self.fiveHour = fiveHour
        self.weekly = weekly
        self.resetCredits = resetCredits
    }
}

public struct TrayQuotaProvider: Decodable, Equatable, Sendable {
    public let provider: String
    public let fiveHour: TrayQuotaWindow?
    public let weekly: TrayQuotaWindow?
    public let blocked: TrayQuotaBlock?
    public let resetCredits: Int
    public let accounts: [TrayQuotaAccount]

    public init(provider: String, fiveHour: TrayQuotaWindow? = nil, weekly: TrayQuotaWindow? = nil,
                blocked: TrayQuotaBlock? = nil, resetCredits: Int = 0, accounts: [TrayQuotaAccount] = []) {
        self.provider = provider
        self.fiveHour = fiveHour
        self.weekly = weekly
        self.blocked = blocked
        self.resetCredits = resetCredits
        self.accounts = accounts
    }
}
