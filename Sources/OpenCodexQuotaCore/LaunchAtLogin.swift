import Foundation

public enum LaunchAtLoginStatus: Sendable {
    case notRegistered
    case enabled
    case requiresApproval
    case notFound
}

@MainActor
public protocol LaunchAtLoginService: AnyObject {
    var status: LaunchAtLoginStatus { get }
    func register() throws
    func unregister() throws
}

@MainActor
public final class LaunchAtLoginController {
    public private(set) var isEnabled = false
    public private(set) var requiresApproval = false
    public private(set) var errorMessage: String?

    private let service: any LaunchAtLoginService

    public init(service: any LaunchAtLoginService) {
        self.service = service
        syncStatus()
    }

    public func refresh() {
        errorMessage = nil
        syncStatus()
    }

    private func syncStatus() {
        let status = service.status
        isEnabled = status == .enabled || status == .requiresApproval
        requiresApproval = status == .requiresApproval
    }

    public func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        syncStatus()
    }
}
