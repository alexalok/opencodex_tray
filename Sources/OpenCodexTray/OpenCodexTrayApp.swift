import AppKit
import PauseWorkerCore
import SwiftUI

@main
struct OpenCodexTrayApp: App {
    @StateObject private var model: TrayViewModel

    init() {
        let model = TrayViewModel.bootstrap()
        _model = StateObject(wrappedValue: model)
        model.startPolling()
    }

    var body: some Scene {
        MenuBarExtra {
            Section("Codex Pool") {
                if model.codexRows.isEmpty {
                    Text(model.errorMessage == nil ? "Loading…" : "Unavailable")
                } else {
                    ForEach(model.codexRows) { row in
                        Text(DisplayFormatter.row(row))
                    }
                }
            }
            Section("Claude Pool") {
                if model.claudeRows.isEmpty {
                    Text(model.errorMessage == nil && model.claudeErrorMessage == nil ? "Loading…" : "Unavailable")
                } else {
                    ForEach(model.claudeRows) { row in
                        Text(DisplayFormatter.row(row))
                    }
                }
            }
            if let error = model.errorMessage {
                Divider()
                Text("Error: \(error)")
            }
            if let error = model.claudeErrorMessage {
                Divider()
                Text("Claude error: \(error)")
            }
            Divider()
            Button("Refresh Now") { Task { await model.refresh() } }
                .keyboardShortcut("r")
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        } label: {
            TrayStatusLabel(
                claudePercentage: model.claudeTrayTitle,
                codexPercentage: model.codexTrayTitle,
                accessibilityLabel: model.trayAccessibilityLabel
            )
        }
        .menuBarExtraStyle(.menu)
    }
}

@MainActor
private struct TrayStatusLabel: View {
    let claudePercentage: String
    let codexPercentage: String
    let accessibilityLabel: String

    @ViewBuilder
    var body: some View {
        if let claudeIcon = ProviderIconStore.cgImage(named: "ProviderIcon-claude"),
           let codexIcon = ProviderIconStore.cgImage(named: "ProviderIcon-codex") {
            Self.statusImage(
                claudeIcon: claudeIcon,
                claudePercentage: claudePercentage,
                codexIcon: codexIcon,
                codexPercentage: codexPercentage,
                accessibilityLabel: accessibilityLabel
            )
        } else {
            Text("Claude \(claudePercentage)  Codex \(codexPercentage)")
                .monospacedDigit()
                .accessibilityLabel(accessibilityLabel)
        }
    }

    private static func statusImage(
        claudeIcon: CGImage,
        claudePercentage: String,
        codexIcon: CGImage,
        codexPercentage: String,
        accessibilityLabel: String
    ) -> Image {
        let height: CGFloat = 16
        let iconSize: CGFloat = 14
        let iconTextGap: CGFloat = 3
        let groupGap: CGFloat = 8
        let fontSize = NSFont.systemFontSize
        let font = NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .regular)
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let claudeTextWidth = ceil((claudePercentage as NSString).size(withAttributes: attributes).width)
        let codexTextWidth = ceil((codexPercentage as NSString).size(withAttributes: attributes).width)
        let width = iconSize + iconTextGap + claudeTextWidth
            + groupGap + iconSize + iconTextGap + codexTextWidth
        let textFont = Font.system(size: fontSize).monospacedDigit()

        return Image(size: CGSize(width: width, height: height), label: Text(accessibilityLabel)) { context in
            var claudeIcon = context.resolve(Image(decorative: claudeIcon, scale: 1))
            claudeIcon.shading = .color(.white)
            context.draw(
                claudeIcon,
                in: CGRect(x: 0, y: 1, width: iconSize, height: iconSize)
            )

            var claudeText = context.resolve(Text(claudePercentage).font(textFont))
            claudeText.shading = .color(.white)
            let claudeTextX = iconSize + iconTextGap
            context.draw(
                claudeText,
                at: CGPoint(x: claudeTextX, y: height / 2),
                anchor: .leading
            )

            let codexIconX = claudeTextX + claudeTextWidth + groupGap
            var codexIcon = context.resolve(Image(decorative: codexIcon, scale: 1))
            codexIcon.shading = .color(.white)
            context.draw(
                codexIcon,
                in: CGRect(x: codexIconX, y: 1, width: iconSize, height: iconSize)
            )

            var codexText = context.resolve(Text(codexPercentage).font(textFont))
            codexText.shading = .color(.white)
            context.draw(
                codexText,
                at: CGPoint(x: codexIconX + iconSize + iconTextGap, y: height / 2),
                anchor: .leading
            )
        }
        .renderingMode(.template)
    }
}

@MainActor
private enum ProviderIconStore {
    private static var cache: [String: CGImage] = [:]
    private static let resourceBundle: Bundle = {
        if let url = Bundle.main.url(
            forResource: "OpenCodexPauseWorker_OpenCodexTray",
            withExtension: "bundle"
        ), let bundle = Bundle(url: url) {
            return bundle
        }
        return Bundle.module
    }()

    static func cgImage(named name: String) -> CGImage? {
        if let cached = cache[name] { return cached }
        guard let url = resourceBundle.url(forResource: name, withExtension: "svg"),
              let image = NSImage(contentsOf: url) else { return nil }
        var rect = NSRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { return nil }
        cache[name] = cgImage
        return cgImage
    }
}

@MainActor
final class TrayViewModel: ObservableObject {
    @Published private(set) var claudeTrayTitle = "…"
    @Published private(set) var codexTrayTitle = "…"
    @Published private(set) var claudeRows: [AccountAllowance] = []
    @Published private(set) var codexRows: [AccountAllowance] = []
    @Published private(set) var errorMessage: String?
    @Published private(set) var claudeErrorMessage: String?

    var trayAccessibilityLabel: String {
        "Claude \(claudeTrayTitle), Codex \(codexTrayTitle)"
    }

    private let worker: PauseWorker?
    private let interval: TimeInterval
    private var pollingTask: Task<Void, Never>?

    init(worker: PauseWorker?, interval: TimeInterval, startupError: String? = nil) {
        self.worker = worker
        self.interval = interval
        self.errorMessage = startupError
        if startupError != nil {
            claudeTrayTitle = "!"
            codexTrayTitle = "!"
        }
    }

    static func bootstrap() -> TrayViewModel {
        do {
            let config = try WorkerConfiguration.load(environment: ProcessInfo.processInfo.environment)
            let token = try AdminTokenReader.read(path: config.adminTokenPath)
            let client = OpenCodexClient(
                baseURL: config.baseURL,
                adminToken: token,
                timeout: config.requestTimeout
            )
            return TrayViewModel(
                worker: PauseWorker(
                    client: client,
                    targetAlias: config.targetAlias,
                    thresholdPercent: config.thresholdPercent
                ),
                interval: config.pollInterval
            )
        } catch {
            return TrayViewModel(worker: nil, interval: 60, startupError: error.localizedDescription)
        }
    }

    func startPolling() {
        guard pollingTask == nil, worker != nil else { return }
        pollingTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await refresh()
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    func refresh() async {
        guard let worker else { return }
        do {
            let result = try await worker.refresh()
            codexRows = result.codexSummary.rows
            codexTrayTitle = DisplayFormatter.trayTitle(result.codexSummary.trayPercentage)
            errorMessage = nil
            if let claudeSummary = result.claudeSummary {
                claudeRows = claudeSummary.rows
                claudeTrayTitle = DisplayFormatter.trayTitle(claudeSummary.trayPercentage)
            } else {
                claudeTrayTitle = "!"
            }
            claudeErrorMessage = result.claudeErrorMessage
        } catch {
            errorMessage = error.localizedDescription
            codexTrayTitle = "!"
        }
    }
}
