import Foundation
import PauseWorkerCore

@main
enum PauseWorkerOnce {
    static func main() async {
        do {
            let config = try WorkerConfiguration.load(environment: ProcessInfo.processInfo.environment)
            let token = try AdminTokenReader.read(path: config.adminTokenPath)
            let client = OpenCodexClient(baseURL: config.baseURL, adminToken: token, timeout: config.requestTimeout)
            let worker = PauseWorker(
                client: client,
                targetAlias: config.targetAlias,
                thresholdPercent: config.thresholdPercent
            )
            let result = try await worker.refresh()
            if let summary = result.claudeSummary {
                print("Claude \(DisplayFormatter.claudeTrayTitle(summary))")
                for row in summary.rows { print(DisplayFormatter.claudeRow(row)) }
            }
            if let error = result.claudeErrorMessage { print("Claude error: \(error)") }
            print("Codex \(DisplayFormatter.trayTitle(result.codexSummary.trayPercentage))")
            for row in result.codexSummary.rows { print(DisplayFormatter.row(row)) }
        } catch {
            FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
            Foundation.exit(EXIT_FAILURE)
        }
    }
}
