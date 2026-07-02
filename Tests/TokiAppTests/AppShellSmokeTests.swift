import SwiftUI
import TokiCore
import XCTest
@testable import TokiApp

@MainActor
final class AppShellSmokeTests: XCTestCase {
    func testSignedInMockUserSelectsRoomAndEnablesManualPTT() {
        let model = AppShellModel()

        model.signInMockUser()

        XCTAssertEqual(model.authenticationState, .signedIn)
        XCTAssertNotNil(model.activeConversationID)
        XCTAssertEqual(model.menuBarStatus, .listening)
        XCTAssertTrue(model.canUseManualPTT)
    }

    func testMicrophoneDeniedDisablesManualPTTAndShowsRecoveryState() {
        let model = AppShellModel()
        model.permissionPreset = .microphoneDenied
        model.signInMockUser()

        model.startManualPushToTalk()

        XCTAssertFalse(model.canUseManualPTT)
        XCTAssertEqual(model.activityLabel, "Microphone permission required")
    }

    func testMenuStatusReflectsRequestingBusyAndPermissionStates() {
        let model = AppShellModel()
        model.signInMockUser()

        model.startManualPushToTalk()
        XCTAssertEqual(model.menuBarStatus, .requestingFloor)

        model.stopPushToTalk()
        model.simulateRemoteSpeaker()
        XCTAssertEqual(model.menuBarStatus, .floorBusy)

        model.permissionPreset = .microphoneDenied
        model.startManualPushToTalk()
        XCTAssertEqual(model.menuBarStatus, .microphoneBlocked)
    }

    func testShortcutPressIsEdgeTriggeredUntilRelease() {
        let model = AppShellModel()
        model.signInMockUser()

        XCTAssertTrue(model.handleShortcutPressed())
        XCTAssertFalse(model.handleShortcutPressed())
        model.handleShortcutReleased()
        XCTAssertTrue(model.handleShortcutPressed())
    }

    func testLivePermissionCoordinatorCanDriveOnboardingRefresh() async {
        let coordinator = MutablePermissionCoordinator(
            microphonePermission: .notDetermined,
            inputMonitoringPermission: .denied,
            requestedMicrophoneResult: .granted
        )
        let model = AppShellModel(permissionCoordinator: coordinator)

        await model.requestMicrophonePermission()
        model.refreshInputMonitoringPermission()

        XCTAssertEqual(coordinator.microphonePermission, .granted)
        XCTAssertEqual(coordinator.inputMonitoringPermission, .denied)
    }

    func testShellViewCanBeConstructedForSmokeCoverage() {
        let model = AppShellModel()
        _ = AppShellView(model: model)
    }
}

private final class MutablePermissionCoordinator: PermissionCoordinating, @unchecked Sendable {
    private(set) var microphonePermission: PermissionStatus
    private(set) var inputMonitoringPermission: PermissionStatus
    private let requestedMicrophoneResult: PermissionStatus

    init(
        microphonePermission: PermissionStatus,
        inputMonitoringPermission: PermissionStatus,
        requestedMicrophoneResult: PermissionStatus
    ) {
        self.microphonePermission = microphonePermission
        self.inputMonitoringPermission = inputMonitoringPermission
        self.requestedMicrophoneResult = requestedMicrophoneResult
    }

    func requestMicrophonePermission() async -> PermissionStatus {
        microphonePermission = requestedMicrophoneResult
        return microphonePermission
    }

    func refreshInputMonitoringPermission() -> PermissionStatus {
        inputMonitoringPermission
    }
}
