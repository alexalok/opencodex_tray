import Foundation
import PauseWorkerCore

@main
enum PauseWorkerOnce {
    static func main() async {
        do {
            let config = try WorkerConfiguration.load(environment: ProcessInfo.processInfo.environment)
            let token = try AdminTokenReader.read(path: config.adminTokenPath)
            let quotaClient = OpenCodexQuotaClient(
                baseURL: config.baseURL,
                adminToken: token,
                timeout: config.requestTimeout
            )
            let worker = PauseWorker(
                loader: QuotaSnapshotLoader(
                    client: quotaClient,
                    targetAlias: config.targetAlias,
                    thresholdPercent: config.thresholdPercent
                ),
                pauser: OpenCodexPauseClient(
                    baseURL: config.baseURL,
                    adminToken: token,
                    timeout: config.requestTimeout
                ),
                targetAlias: config.targetAlias,
                thresholdPercent: config.thresholdPercent
            )
            let result = try await worker.refresh()
            if let summary = result.snapshot.claudeSummary {
                print("Claude \(DisplayFormatter.claudeTrayTitle(summary))")
                for row in summary.rows { print(DisplayFormatter.claudeRow(row)) }
            }
            if let error = result.snapshot.claudeErrorMessage { print("Claude error: \(error)") }
            if let summary = result.snapshot.codexSummary {
                print("Codex \(DisplayFormatter.trayTitle(summary.trayPercentage))")
                for row in summary.rows { print(DisplayFormatter.row(row)) }
            }
            if let error = result.snapshot.codexErrorMessage { print("Codex error: \(error)") }
        } catch {
            FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
            Foundation.exit(EXIT_FAILURE)
        }
    }
}
