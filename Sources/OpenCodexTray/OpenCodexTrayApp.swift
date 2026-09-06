import AppKit
import Darwin
import OpenCodexQuotaCore
import OSLog
import ServiceManagement
import SwiftUI
import WidgetKit

@main
struct OpenCodexTrayApp: App {
    @StateObject private var model: TrayViewModel

    init() {
        if CommandLine.arguments.contains("--verify-resources") {
            ProviderIconStore.verifyResourcesAndExit()
        }

        let model = TrayViewModel.bootstrap()
        _model = StateObject(wrappedValue: model)
        model.startPolling()
    }

    var body: some Scene {
        MenuBarExtra {
            Group {
            Section("Codex Pool") {
                if model.codexRows.isEmpty {
                    Text(model.errorMessage == nil ? "Loading…" : "Unavailable")
                } else {
                    ForEach(model.codexRows) { row in
                        Text(DisplayFormatter.row(row))
                    }
                }
            }
            Section("Claude Pool (5h/1w)") {
                if model.claudeRows.isEmpty {
                    Text(model.errorMessage == nil && model.claudeErrorMessage == nil ? "Loading…" : "Unavailable")
                } else {
                    ForEach(model.claudeRows) { row in
                        Text(DisplayFormatter.claudeRow(row))
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
            Toggle("Launch at Login", isOn: Binding(
                get: { model.launchAtLoginEnabled },
                set: { model.setLaunchAtLogin($0) }
            ))
            if model.launchAtLoginRequiresApproval {
                Text("Launch at login requires approval")
                Button("Open Login Items Settings") {
                    SMAppService.openSystemSettingsLoginItems()
                }
            }
            if let error = model.launchAtLoginErrorMessage {
                Text("Launch at login: \(error)")
            }
            Divider()
            Button("Refresh Now") { Task { await model.refresh() } }
                .keyboardShortcut("r")
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
            }
            .onAppear { model.refreshLaunchAtLogin() }
        } label: {
            TrayStatusLabel(
                claudeLimits: model.claudeTrayTitle,
                codexPercentage: model.codexTrayTitle,
                accessibilityLabel: model.trayAccessibilityLabel
            )
        }
        .menuBarExtraStyle(.menu)
    }
}

@MainActor
private struct TrayStatusLabel: View {
    let claudeLimits: String
    let codexPercentage: String
    let accessibilityLabel: String

    @ViewBuilder
    var body: some View {
        if let claudeIcon = ProviderIconStore.cgImage(named: "ProviderIcon-claude"),
           let codexIcon = ProviderIconStore.cgImage(named: "ProviderIcon-codex") {
            Self.statusImage(
                claudeIcon: claudeIcon,
                claudeLimits: claudeLimits,
                codexIcon: codexIcon,
                codexPercentage: codexPercentage,
                accessibilityLabel: accessibilityLabel
            )
        } else {
            Text("Claude \(claudeLimits)  Codex \(codexPercentage)")
                .monospacedDigit()
                .accessibilityLabel(accessibilityLabel)
        }
    }

    private static func statusImage(
        claudeIcon: CGImage,
        claudeLimits: String,
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
        let claudeTextWidth = ceil((claudeLimits as NSString).size(withAttributes: attributes).width)
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

            var claudeText = context.resolve(Text(claudeLimits).font(textFont))
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
    private static let bundleName = "OpenCodexQuotaTray_OpenCodexTray"
    private static var cache: [String: CGImage] = [:]
    private static let resourceBundle: Bundle? = {
        if let url = Bundle.main.url(
            forResource: bundleName,
            withExtension: "bundle"
        ), let bundle = Bundle(url: url) {
            return bundle
        }

        let executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
            .standardizedFileURL
            .deletingLastPathComponent()
        if let bundle = Bundle(
            url: executableURL.appendingPathComponent("\(bundleName).bundle")
        ) {
            return bundle
        }

        let names = ["ProviderIcon-claude", "ProviderIcon-codex"]
        if names.allSatisfy({
            Bundle.main.url(forResource: $0, withExtension: "svg") != nil
        }) {
            return Bundle.main
        }

        return nil
    }()

    static func cgImage(named name: String) -> CGImage? {
        if let cached = cache[name] { return cached }
        guard let url = resourceBundle?.url(forResource: name, withExtension: "svg"),
              let image = NSImage(contentsOf: url) else { return nil }
        var rect = NSRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { return nil }
        cache[name] = cgImage
        return cgImage
    }

    static func verifyResourcesAndExit() -> Never {
        let names = ["ProviderIcon-claude", "ProviderIcon-codex"]
        let resourcesAvailable = names.allSatisfy { cgImage(named: $0) != nil }
        print(resourcesAvailable ? "Resources OK" : "Resources unavailable")
        Darwin.exit(resourcesAvailable ? EXIT_SUCCESS : EXIT_FAILURE)
    }
}

@MainActor
final class TrayViewModel: ObservableObject {
    private static let logger = Logger(
        subsystem: "local.opencodex.quota-tray",
        category: "widget-configuration"
    )

    @Published private(set) var claudeTrayTitle = "…"
    @Published private(set) var codexTrayTitle = "…"
    @Published private(set) var claudeRows: [ClaudeAccountAllowance] = []
    @Published private(set) var codexRows: [AccountAllowance] = []
    @Published private(set) var errorMessage: String?
    @Published private(set) var claudeErrorMessage: String?
    @Published private(set) var launchAtLoginEnabled = false
    @Published private(set) var launchAtLoginRequiresApproval = false
    @Published private(set) var launchAtLoginErrorMessage: String?

    var trayAccessibilityLabel: String {
        "Claude \(claudeTrayTitle), Codex \(codexTrayTitle)"
    }

    private let refresher: QuotaRefresher?
    private let launchAtLoginController: LaunchAtLoginController
    private let interval: TimeInterval
    private var pollingTask: Task<Void, Never>?

    init(
        refresher: QuotaRefresher?,
        interval: TimeInterval,
        startupError: String? = nil,
        launchAtLoginService: any LaunchAtLoginService = MainAppLaunchAtLoginService()
    ) {
        self.refresher = refresher
        self.interval = interval
        self.launchAtLoginController = LaunchAtLoginController(service: launchAtLoginService)
        self.errorMessage = startupError
        if startupError != nil {
            claudeTrayTitle = "!"
            codexTrayTitle = "!"
        }
        syncLaunchAtLoginState()
    }

    static func bootstrap() -> TrayViewModel {
        do {
            let config = try TrayConfiguration.load(environment: ProcessInfo.processInfo.environment)
            let token = try AdminTokenReader.read(path: config.adminTokenPath)
            do {
                let widgetConfiguration = WidgetConnectionConfiguration(
                    baseURL: config.baseURL,
                    adminToken: token,
                    requestTimeout: config.requestTimeout
                )
                try WidgetConfigurationStore.shared().save(widgetConfiguration)
                WidgetCenter.shared.reloadAllTimelines()
            } catch {
                Self.logger.error(
                    "Failed to sync widget configuration: \(error.localizedDescription, privacy: .public)"
                )
            }
            let client = OpenCodexClient(
                baseURL: config.baseURL,
                adminToken: token,
                timeout: config.requestTimeout
            )
            let loader = QuotaSnapshotLoader(client: client)
            return TrayViewModel(
                refresher: QuotaRefresher(loader: loader),
                interval: config.pollInterval
            )
        } catch {
            return TrayViewModel(refresher: nil, interval: 60, startupError: error.localizedDescription)
        }
    }

    func startPolling() {
        guard pollingTask == nil, refresher != nil else { return }
        pollingTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await refresh()
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    func refreshLaunchAtLogin() {
        launchAtLoginController.refresh()
        syncLaunchAtLoginState()
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        launchAtLoginController.setEnabled(enabled)
        syncLaunchAtLoginState()
    }

    private func syncLaunchAtLoginState() {
        launchAtLoginEnabled = launchAtLoginController.isEnabled
        launchAtLoginRequiresApproval = launchAtLoginController.requiresApproval
        launchAtLoginErrorMessage = launchAtLoginController.errorMessage
    }

    func refresh() async {
        guard let refresher else { return }
        let snapshot = await refresher.refresh().snapshot
        if let codexSummary = snapshot.codexSummary {
            codexRows = codexSummary.rows
            codexTrayTitle = DisplayFormatter.trayTitle(codexSummary.trayPercentage)
            errorMessage = nil
        } else {
            codexTrayTitle = "!"
            errorMessage = snapshot.codexErrorMessage
        }
        if let claudeSummary = snapshot.claudeSummary {
            claudeRows = claudeSummary.rows
            claudeTrayTitle = DisplayFormatter.claudeTrayTitle(claudeSummary)
            claudeErrorMessage = nil
        } else {
            claudeTrayTitle = "!"
            claudeErrorMessage = snapshot.claudeErrorMessage
        }
    }
}

@MainActor
private final class MainAppLaunchAtLoginService: LaunchAtLoginService {
    private let service = SMAppService.mainApp

    var status: LaunchAtLoginStatus {
        switch service.status {
        case .notRegistered: .notRegistered
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        case .notFound: .notFound
        @unknown default: .notFound
        }
    }

    func register() throws {
        try service.register()
    }

    func unregister() throws {
        try service.unregister()
    }
}
