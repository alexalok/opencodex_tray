import XCTest
@testable import PauseWorkerCore

final class SubscriptionBaselineTests: XCTestCase {
    func testCodexCurrentBaselineRescalesAcrossPricedPlans() throws {
        let accounts = [OpenCodexAccount(id: "a", alias: "target", plan: "prolite", isMain: false,
            paused: false, weeklyUsedPercent: 20, fiveHourUsedPercent: 0)]
        let pro = try QuotaCalculator.summarize(accounts: accounts, targetAlias: "target", thresholdPercent: 70)
        let lite = try QuotaCalculator.summarize(accounts: accounts, targetAlias: "target", thresholdPercent: 70, baseline: .proLite)
        XCTAssertEqual(pro.trayPercentage, 25)
        XCTAssertEqual(lite.trayPercentage, 50)
        XCTAssertEqual(lite.rows[0].totalPercent, 70)
        let plus = try QuotaCalculator.summarize(accounts: accounts, targetAlias: "target", thresholdPercent: 70, baseline: .plus)
        XCTAssertEqual(plus.trayPercentage, 500)
        XCTAssertTrue(plus.hideFromTray)
        let native = try QuotaCalculator.summarize(accounts: accounts, targetAlias: "target", thresholdPercent: 70, baseline: .native)
        XCTAssertEqual(native.trayPercentage, 50)
    }

    func testCodexPlusBaselineSupportsPlusAndUnknownPlansStayVisible() throws {
        let plus = OpenCodexAccount(id: "a", alias: "target", plan: "plus", isMain: false,
            paused: false, weeklyUsedPercent: 0, fiveHourUsedPercent: 0)
        let summary = try QuotaCalculator.summarize(accounts: [plus], targetAlias: "target", thresholdPercent: 100, baseline: .plus)
        XCTAssertEqual(summary.trayPercentage, 100)
        XCTAssertTrue(summary.hideFromTray)
        let pro = try QuotaCalculator.summarize(accounts: [plus], targetAlias: "target", thresholdPercent: 100)
        XCTAssertEqual(pro.trayPercentage, 5)
        XCTAssertFalse(pro.hideFromTray)
    }

    func testCodexProMaxAndUncappedProWindows() throws {
        let accounts = [OpenCodexAccount(id: "a", alias: "target", plan: "promax", isMain: false,
            paused: false, weeklyUsedPercent: 20, fiveHourUsedPercent: nil)]
        let pro = try QuotaCalculator.summarize(accounts: accounts, targetAlias: "target", thresholdPercent: 100)
        XCTAssertEqual(pro.trayPercentage, 200)
        XCTAssertTrue(pro.hideFromTray)
        let max = try QuotaCalculator.summarize(accounts: accounts, targetAlias: "target", thresholdPercent: 100, baseline: .proMax)
        XCTAssertEqual(max.trayPercentage, 80)
        XCTAssertFalse(max.hideFromTray)
    }

    func testClaudeWindowSpecificRatiosAndUltraSessionRemainUnknown() {
        let accounts = [ClaudeAccount(id: "a", alias: nil, email: nil, plan: "max_5x",
            fiveHourUsedPercent: 20, weeklyUsedPercent: 30)]
        let pro = ClaudeQuotaCalculator.summarize(accounts: accounts, baseline: .pro)
        XCTAssertEqual(pro.fiveHourRemainingPercentage, 400)
        XCTAssertEqual(pro.weeklyRemainingPercentage, 350)
        XCTAssertTrue(pro.hideFromTray)
        let sameTier = ClaudeQuotaCalculator.summarize(accounts: accounts, baseline: .max5x)
        XCTAssertEqual(sameTier.fiveHourRemainingPercentage, 80)
        XCTAssertEqual(sameTier.weeklyRemainingPercentage, 70)
        let larger = ClaudeQuotaCalculator.summarize(accounts: accounts, baseline: .ultra)
        XCTAssertNil(larger.fiveHourRemainingPercentage)
        XCTAssertEqual(larger.weeklyRemainingPercentage, 35)
        let ultraAccount = ClaudeAccount(id: "u", alias: nil, email: nil, plan: "max_20x",
            fiveHourUsedPercent: 0, weeklyUsedPercent: 30)
        let ultraAsPro = ClaudeQuotaCalculator.summarize(accounts: [ultraAccount], baseline: .pro)
        XCTAssertNil(ultraAsPro.fiveHourRemainingPercentage)
        XCTAssertEqual(ultraAsPro.weeklyRemainingPercentage, 700)
        XCTAssertFalse(ultraAsPro.hideFromTray)
    }

    func testClaudeUnknownTierDoesNotMasqueradeAsPro() {
        for plan in [nil, "max", "team", "enterprise", "future"] as [String?] {
            let accounts = [ClaudeAccount(id: "a", alias: nil, email: nil, plan: plan,
                fiveHourUsedPercent: 20, weeklyUsedPercent: 30)]
            let normalized = ClaudeQuotaCalculator.summarize(accounts: accounts, baseline: .pro)
            XCTAssertNil(normalized.fiveHourRemainingPercentage)
            XCTAssertNil(normalized.weeklyRemainingPercentage)
            let native = ClaudeQuotaCalculator.summarize(accounts: accounts)
            XCTAssertEqual(native.fiveHourRemainingPercentage, 80)
            XCTAssertEqual(native.weeklyRemainingPercentage, 70)
        }
    }

    func testBaselinePreferencesPersistIndependentlyAndRejectInvalidValues() {
        let suite = "SubscriptionBaselineTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SubscriptionSettingsStore(defaults: defaults)
        XCTAssertEqual(store.load(), SubscriptionSettings())
        store.save(SubscriptionSettings(codex: .proLite, claude: .max5x))
        XCTAssertEqual(SubscriptionSettingsStore(defaults: defaults).load(),
            SubscriptionSettings(codex: .proLite, claude: .max5x))
        defaults.set("future-tier", forKey: "codexBaseline")
        XCTAssertEqual(store.load().codex, .pro)
        XCTAssertEqual(store.load().claude, .max5x)
    }

    func testClaudePlanSurvivesDecodingForNormalization() throws {
        let data = Data(#"{"accounts":[{"id":"a","plan":"max_5x","quota":{"fiveHourPercent":20,"weeklyPercent":30}}]}"#.utf8)
        let accounts = try OpenCodexResponseDecoder.decodeClaudeAccounts(data)
        XCTAssertEqual(accounts.first?.plan, "max_5x")
    }
}
