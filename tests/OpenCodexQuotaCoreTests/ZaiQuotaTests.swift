import Foundation
import Testing
@testable import OpenCodexQuotaCore

struct ZaiQuotaTests {
    @Test func selectsSourceAndKeepsMissingWindowsUnknown() throws {
        let data = Data(#"{"reports":[{"provider":"custom-glm","label":"GLM work","source":"zai:quota-limit","quota":{"fiveHourPercent":25}},{"provider":"anthropic","source":"anthropic:oauth-usage","quota":{"fiveHourPercent":90}}]}"#.utf8)
        let summary = try ZaiQuotaDecoder.decode(data)
        #expect(summary.rows.count == 1)
        #expect(summary.rows.first?.id == "custom-glm")
        #expect(summary.rows.first?.label == "GLM work")
        #expect(summary.fiveHourRemainingPercentage == 75)
        #expect(summary.weeklyRemainingPercentage == nil)
    }

    @Test func rejectsInvalidAndDuplicateQuota() {
        for reports in [
            #"[{"provider":"zai","source":"zai:quota-limit","quota":{"fiveHourPercent":101}}]"#,
            #"[{"provider":"zai","source":"zai:quota-limit","quota":{}},{"provider":"zai","source":"zai:quota-limit","quota":{}}]"#
        ] {
            #expect(throws: (any Error).self) { try ZaiQuotaDecoder.decode(Data("{\"reports\":\(reports)}".utf8)) }
        }
    }

    private struct FailedZaiClient: OpenCodexQuotaServing {
        func fetchAccounts() async throws -> [OpenCodexAccount] { [] }
        func fetchClaudeAccounts() async throws -> [ClaudeAccount] { [] }
        func fetchZaiQuota() async throws -> ClaudeQuotaSummary? { throw ConfigurationError.invalid("secret") }
    }
    @Test func zaiFailureDoesNotBreakOtherProvidersOrLeakErrors() async {
        let snapshot = await QuotaSnapshotLoader(client: FailedZaiClient()).load().snapshot
        #expect(snapshot.codexSummary != nil)
        #expect(snapshot.claudeSummary != nil)
        #expect(snapshot.zaiSummary == nil)
        #expect(snapshot.zaiErrorMessage == "OpenCodex Z.ai quota unavailable")
        #expect(snapshot.isComplete)
    }

    @Test func snapshotRoundTripAndLegacyCache() throws {
        let legacy = Data(#"{"fetchedAt":0}"#.utf8)
        let snapshot = try JSONDecoder().decode(QuotaSnapshot.self, from: legacy)
        #expect(snapshot.zaiSummary == nil)
        let summary = try ZaiQuotaDecoder.decode(Data(#"{"reports":[{"provider":"zai","source":"zai:quota-limit","quota":{"weeklyPercent":5}}]}"#.utf8))
        let current = QuotaSnapshot(zaiSummary: summary, fetchedAt: Date(), codexSummary: nil,
            codexErrorMessage: nil, claudeSummary: nil, claudeErrorMessage: nil)
        #expect(current.hasProviderData)
        #expect(try JSONDecoder().decode(QuotaSnapshot.self, from: JSONEncoder().encode(current)) == current)
    }

    @Test func missingOrInvalidSourcesDoNotHideZai() throws {
        let data = Data(#"{"reports":[{"provider":"other"},{"source":null},{"source":42},{"provider":"zai","source":"zai:quota-limit","quota":{"weeklyPercent":25}}]}"#.utf8)
        #expect(try ZaiQuotaDecoder.decode(data).weeklyRemainingPercentage == 75)
    }

    @Test func unrelatedReportsDoNotRequireQuotaShape() throws {
        let summary = try ZaiQuotaDecoder.decode(Data(#"{"reports":[{"provider":"other","source":"other","quota":"future format"}]}"#.utf8))
        #expect(summary.rows.isEmpty)
    }
}
