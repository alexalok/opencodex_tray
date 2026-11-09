import AppKit
import Combine
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
            Text(model.sourceLabel)
            Section("Codex Pool (5h/1w)") {
                if model.codexRows.isEmpty {
                    Text(!model.codexEnabled ? "Disabled" : model.errorMessage == nil ? "No accounts" : "Unavailable")
                } else {
                    ForEach(model.codexRows) { row in
                        if let expiry = DisplayFormatter.resetExpiry(row, now: model.displayDate) {
                            Text(DisplayFormatter.row(row)).strikethrough(row.paused)
                                + Text(" (\(Image(systemName: "ticket")) \(expiry))")
                        } else {
                            Text(DisplayFormatter.row(row)).strikethrough(row.paused)
                        }
                    }
                }
            }
            Section("Claude Pool (5h/1w)") {
                if model.claudeRows.isEmpty {
                    Text(!model.claudeEnabled ? "Disabled" : model.claudeErrorMessage == nil ? "No accounts" : "Unavailable")
                } else {
                    ForEach(model.claudeRows) { row in
                        Text(DisplayFormatter.claudeRow(row))
                    }
                }
            }
            if !model.zaiRows.isEmpty || model.zaiErrorMessage != nil {
                Section("Z.ai Coding Plan (5h/1w)") {
                    ForEach(model.zaiRows) { row in Text(DisplayFormatter.claudeRow(row)) }
                    if let error = model.zaiErrorMessage { Text(error) }
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
                providers: model.trayProviders,
                accessibilityLabel: model.trayAccessibilityLabel
            )
        }
        .menuBarExtraStyle(.menu)
    }
}

/// One provider group in the menu-bar label. Hidden providers are simply absent.
struct TrayProviderLabel: Equatable {
    let name: String
    let iconName: String
    let text: String
    let hasExpiringReset: Bool
}

@MainActor
private struct TrayStatusLabel: View {
    let providers: [TrayProviderLabel]
    let accessibilityLabel: String

    @ViewBuilder
    var body: some View {
        if providers.isEmpty {
            // Every provider has ample quota; keep the menu reachable.
            Image(systemName: "chart.bar")
                .accessibilityLabel(accessibilityLabel)
        } else {
            Self.statusImage(providers: providers, accessibilityLabel: accessibilityLabel)
        }
    }

    private struct Group {
        let icon: CGImage?
        let text: String
        let textWidth: CGFloat
        let hasExpiringReset: Bool
    }

    private static func statusImage(providers: [TrayProviderLabel], accessibilityLabel: String) -> Image {
        let height: CGFloat = 16
        let iconSize: CGFloat = 14
        let iconTextGap: CGFloat = 3
        let groupGap: CGFloat = 8
        let fontSize = NSFont.systemFontSize
        let font = NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .regular)
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        func textWidth(_ text: String) -> CGFloat {
            ceil((text as NSString).size(withAttributes: attributes).width)
        }
        let groups = providers.map { provider in
            // A provider without a bundled icon falls back to its name inside the label.
            let icon = ProviderIconStore.cgImage(named: provider.iconName)
            let text = icon == nil ? "\(provider.name) \(provider.text)" : provider.text
            return Group(icon: icon, text: text, textWidth: textWidth(text), hasExpiringReset: provider.hasExpiringReset)
        }
        let markWidth = textWidth("!")
        let warningWidth = iconTextGap + iconSize + iconTextGap + markWidth
        func groupWidth(_ group: Group) -> CGFloat {
            (group.icon == nil ? 0 : iconSize + iconTextGap) + group.textWidth
                + (group.hasExpiringReset ? warningWidth : 0)
        }
        let width = groups.reduce(CGFloat.zero) { $0 + groupWidth($1) }
            + CGFloat(max(groups.count - 1, 0)) * groupGap
        let textFont = Font.system(size: fontSize).monospacedDigit()

        return Image(size: CGSize(width: width, height: height), label: Text(accessibilityLabel)) { context in
            var x: CGFloat = 0
            for group in groups {
                var textX = x
                if let groupIcon = group.icon {
                    var icon = context.resolve(Image(decorative: groupIcon, scale: 1))
                    icon.shading = .color(.white)
                    context.draw(icon, in: CGRect(x: x, y: 1, width: iconSize, height: iconSize))
                    textX += iconSize + iconTextGap
                }
                var text = context.resolve(Text(group.text).font(textFont))
                text.shading = .color(.white)
                context.draw(text, at: CGPoint(x: textX, y: height / 2), anchor: .leading)
                if group.hasExpiringReset {
                    let ticketX = textX + group.textWidth + iconTextGap
                    var ticket = context.resolve(Image(systemName: "ticket"))
                    ticket.shading = .color(.white)
                    context.draw(ticket, in: CGRect(x: ticketX, y: 1, width: iconSize, height: iconSize))
                    var mark = context.resolve(Text("!").font(textFont))
                    mark.shading = .color(.white)
                    context.draw(mark, at: CGPoint(x: ticketX + iconSize + iconTextGap, y: height / 2), anchor: .leading)
                }
                x += groupWidth(group) + groupGap
            }
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
        let names = ["ProviderIcon-claude", "ProviderIcon-codex", "ProviderIcon-zai"]
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

    // Native menu-bar labels need a direct Image/Text view. Drive time updates
    // through observable state instead of wrapping menu content in TimelineView.
    @Published private(set) var displayDate = Date()
    private var displayClock: AnyCancellable?

    var hasExpiringReset: Bool {
        codexRows.contains { $0.expiringReset(at: displayDate) != nil }
    }

    // Ample-quota hiding from the last successful refresh; errors and disabled providers reset it.
    @Published private(set) var codexHasAmpleQuota = false
    @Published private(set) var claudeHasAmpleQuota = false
    @Published private(set) var zaiHasAmpleQuota = false

    /// An expiring banked reset is actionable, so it keeps Codex in the menu bar.
    var hideCodexFromTray: Bool { codexHasAmpleQuota && !hasExpiringReset }
    var hideClaudeFromTray: Bool { claudeHasAmpleQuota }
    var hideZaiFromTray: Bool { zaiHasAmpleQuota }

    var trayProviders: [TrayProviderLabel] {
        var providers: [TrayProviderLabel] = []
        if !hideClaudeFromTray {
            providers.append(TrayProviderLabel(name: "Claude", iconName: "ProviderIcon-claude", text: claudeTrayTitle, hasExpiringReset: false))
        }
        if !hideCodexFromTray {
            providers.append(TrayProviderLabel(name: "Codex", iconName: "ProviderIcon-codex", text: codexTrayTitle, hasExpiringReset: hasExpiringReset))
        }
        if let zaiTrayTitle, !hideZaiFromTray {
            providers.append(TrayProviderLabel(name: "Z.ai", iconName: "ProviderIcon-zai", text: zaiTrayTitle, hasExpiringReset: false))
        }
        return providers
    }

    @Published private(set) var zaiRows: [ClaudeAccountAllowance] = []
    @Published private(set) var zaiTrayTitle: String?
    @Published private(set) var zaiErrorMessage: String?
    @Published private(set) var sourceLabel = "Connecting to OpenCodex…"
    @Published private(set) var codexEnabled = true
    @Published private(set) var claudeEnabled = true
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
        let providers = trayProviders
        guard !providers.isEmpty else {
            return "OpenCodex Quota Tray, every pool above \(Int(TrayVisibility.hideThresholdPercent))% remaining"
        }
        var parts = providers.map { "\($0.name) \($0.text)" }
        if providers.contains(where: { $0.name == "Z.ai" }) { parts.append("5-hour / 1-week remaining") }
        if hasExpiringReset { parts.append("banked reset expires in less than 7 days") }
        return parts.joined(separator: ", ")
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
        displayClock = Timer.publish(every: 60, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] date in self?.displayDate = date }
    }

    static func bootstrap() -> TrayViewModel {
        do {
            let config = try TrayConfiguration.load(environment: ProcessInfo.processInfo.environment)
            let logger = Self.logger
            let loader = AdaptiveQuotaSnapshotLoader(configuration: config) { connection in
                do {
                    let store = try WidgetConfigurationStore.shared()
                    let widgetConfig = WidgetConnectionConfiguration(
                        baseURL: config.baseURL, adminToken: "", requestTimeout: config.requestTimeout,
                        connection: connection
                    )
                    if (try? store.load()) != widgetConfig {
                        try store.save(widgetConfig)
                        WidgetCenter.shared.reloadAllTimelines()
                    }
                } catch {
                    logger.error("Failed to sync widget connection: \(error.localizedDescription, privacy: .public)")
                }
            }
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
        displayDate = Date()
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
        displayDate = Date()
        sourceLabel = snapshot.sourceLabel ?? "OpenCodex source unavailable"
        codexEnabled = snapshot.codexEnabled ?? true
        claudeEnabled = snapshot.claudeEnabled ?? true
        zaiRows = snapshot.zaiSummary?.rows ?? []
        zaiErrorMessage = snapshot.zaiErrorMessage
        zaiTrayTitle = snapshot.zaiSummary.flatMap { $0.rows.isEmpty ? nil : DisplayFormatter.claudeTrayTitle($0) }
            ?? (snapshot.zaiErrorMessage == nil ? nil : "!")
        zaiHasAmpleQuota = snapshot.zaiErrorMessage == nil && snapshot.zaiSummary?.hideFromTray == true
        codexRows = []
        claudeRows = []
        if let codexSummary = snapshot.codexSummary {
            codexRows = codexSummary.rows
            codexTrayTitle = codexEnabled ? DisplayFormatter.codexTrayTitle(codexSummary) : "–"
            codexHasAmpleQuota = codexEnabled && codexSummary.hideFromTray
            errorMessage = nil
        } else {
            codexTrayTitle = "!"
            codexHasAmpleQuota = false
            errorMessage = snapshot.codexErrorMessage
        }
        if let claudeSummary = snapshot.claudeSummary {
            claudeRows = claudeSummary.rows
            claudeTrayTitle = claudeEnabled ? DisplayFormatter.claudeTrayTitle(claudeSummary) : "–"
            claudeHasAmpleQuota = claudeEnabled && claudeSummary.hideFromTray
            claudeErrorMessage = nil
        } else {
            claudeTrayTitle = "!"
            claudeHasAmpleQuota = false
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
