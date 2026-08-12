import XCTest
@testable import PauseWorkerCore

@MainActor
final class LaunchAtLoginTests: XCTestCase {
    func testInitialStateReflectsRegistration() {
        let service = FakeLaunchAtLoginService(status: .enabled)
        let controller = LaunchAtLoginController(service: service)

        XCTAssertTrue(controller.isEnabled)
        XCTAssertFalse(controller.requiresApproval)
        XCTAssertNil(controller.errorMessage)
    }

    func testEnablingRegistersAndResyncsState() {
        let service = FakeLaunchAtLoginService(status: .notRegistered)
        let controller = LaunchAtLoginController(service: service)

        controller.setEnabled(true)

        XCTAssertEqual(service.registerCallCount, 1)
        XCTAssertTrue(controller.isEnabled)
        XCTAssertNil(controller.errorMessage)
    }

    func testDisablingUnregistersAndResyncsState() {
        let service = FakeLaunchAtLoginService(status: .enabled)
        let controller = LaunchAtLoginController(service: service)

        controller.setEnabled(false)

        XCTAssertEqual(service.unregisterCallCount, 1)
        XCTAssertFalse(controller.isEnabled)
        XCTAssertNil(controller.errorMessage)
    }

    func testApprovalRequiredCountsAsEnabledAndShowsNotice() {
        let service = FakeLaunchAtLoginService(status: .requiresApproval)
        let controller = LaunchAtLoginController(service: service)

        XCTAssertTrue(controller.isEnabled)
        XCTAssertTrue(controller.requiresApproval)
    }

    func testFailedMutationReportsErrorAndRestoresServiceState() {
        let service = FakeLaunchAtLoginService(status: .notRegistered)
        service.registerError = TestError.registrationFailed
        let controller = LaunchAtLoginController(service: service)

        controller.setEnabled(true)

        XCTAssertFalse(controller.isEnabled)
        XCTAssertEqual(controller.errorMessage, "registration failed")
    }

    func testRefreshClearsStaleMutationErrorAfterExternalRecovery() {
        let service = FakeLaunchAtLoginService(status: .notRegistered)
        service.registerError = TestError.registrationFailed
        let controller = LaunchAtLoginController(service: service)
        controller.setEnabled(true)

        service.status = .enabled
        controller.refresh()

        XCTAssertTrue(controller.isEnabled)
        XCTAssertNil(controller.errorMessage)
    }
}

private final class FakeLaunchAtLoginService: LaunchAtLoginService {
    var status: LaunchAtLoginStatus
    var registerError: Error?
    var unregisterError: Error?
    private(set) var registerCallCount = 0
    private(set) var unregisterCallCount = 0

    init(status: LaunchAtLoginStatus) {
        self.status = status
    }

    func register() throws {
        registerCallCount += 1
        if let registerError { throw registerError }
        status = .enabled
    }

    func unregister() throws {
        unregisterCallCount += 1
        if let unregisterError { throw unregisterError }
        status = .notRegistered
    }
}

private enum TestError: LocalizedError {
    case registrationFailed

    var errorDescription: String? { "registration failed" }
}
