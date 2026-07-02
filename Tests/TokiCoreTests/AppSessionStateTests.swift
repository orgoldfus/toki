import XCTest
@testable import TokiCore

final class AppSessionStateTests: XCTestCase {
    func testSelectingConversationMovesConnectedUserIntoListeningRoom() {
        let session = AppSessionState.mockSignedIn()

        session.selectConversation(id: ConversationID("design"))

        XCTAssertEqual(session.activeConversationID, ConversationID("design"))
        XCTAssertEqual(session.realtimeConnection, .listening)
        XCTAssertEqual(session.floor, .idle)
        XCTAssertEqual(session.activity, .listening)
    }

    func testSessionExposesAuthPermissionsAndDevicePreferences() {
        let preferences = DevicePreferences(
            selectedInputDeviceID: "input-built-in",
            selectedOutputDeviceID: "output-system",
            pushToTalkShortcut: PushToTalkShortcut(keyCode: 49, modifiers: [.command, .shift]),
            launchAtLogin: false,
            diagnosticsOptIn: true
        )
        let session = AppSessionState(
            localUserID: UserID("local-user"),
            permissions: PermissionCoordinator(
                microphonePermission: .granted,
                inputMonitoringPermission: .denied
            ),
            devicePreferences: preferences
        )

        XCTAssertEqual(session.auth, .signedIn(userID: UserID("local-user")))
        XCTAssertEqual(session.permissionState, PermissionState(microphone: .granted, inputMonitoring: .denied))
        XCTAssertEqual(session.devicePreferences, preferences)
    }

    func testHoldingPTTRequestsFloorThenGrantedFloorSpeaksUntilRelease() {
        let session = AppSessionState.mockSignedIn(
            microphone: .granted,
            inputMonitoring: .granted
        )
        session.selectConversation(id: ConversationID("ops"))

        session.pushToTalkPressed(source: .keyboard)

        XCTAssertEqual(session.floor, .requesting(localUserID: session.localUserID))
        XCTAssertEqual(session.activity, .requestingFloor)

        session.floorGrantReceived(speakerID: session.localUserID)

        XCTAssertEqual(session.floor, .granted(speakerID: session.localUserID))
        XCTAssertEqual(session.activity, .speaking)

        session.pushToTalkReleased()

        XCTAssertEqual(session.floor, .idle)
        XCTAssertEqual(session.activity, .listening)
    }

    func testDeniedMicrophoneFailsClosedAndDisablesPTT() {
        let session = AppSessionState.mockSignedIn(
            microphone: .denied,
            inputMonitoring: .granted
        )
        session.selectConversation(id: ConversationID("ops"))

        session.pushToTalkPressed(source: .mouse)

        XCTAssertEqual(session.floor, .blocked(reason: .microphoneDenied))
        XCTAssertEqual(session.activity, .permissionDenied(.microphone))
        XCTAssertFalse(session.canStartPushToTalk(source: .mouse))
    }

    func testUnavailableInputMonitoringBlocksKeyboardButAllowsMousePTT() {
        let session = AppSessionState.mockSignedIn(
            microphone: .granted,
            inputMonitoring: .denied
        )
        session.selectConversation(id: ConversationID("ops"))

        XCTAssertFalse(session.canStartPushToTalk(source: .keyboard))
        XCTAssertTrue(session.canStartPushToTalk(source: .mouse))

        session.pushToTalkPressed(source: .mouse)

        XCTAssertEqual(session.floor, .requesting(localUserID: session.localUserID))
        XCTAssertEqual(session.activity, .requestingFloor)
    }

    func testRemoteSpeakerMakesLocalUserFloorBusy() {
        let session = AppSessionState.mockSignedIn()
        session.selectConversation(id: ConversationID("design"))

        session.floorGrantReceived(speakerID: UserID("teammate"))

        XCTAssertEqual(session.floor, .busy(speakerID: UserID("teammate")))
        XCTAssertEqual(session.activity, .floorBusy)
    }

    func testPTTIsBlockedWhileConnectionIsUnsafeOrFloorIsBusy() {
        let session = AppSessionState.mockSignedIn()
        session.selectConversation(id: ConversationID("design"))

        session.connectionChanged(.reconnecting)
        XCTAssertFalse(session.canStartPushToTalk(source: .mouse))
        session.pushToTalkPressed(source: .mouse)
        XCTAssertEqual(session.activity, .reconnecting)

        session.connectionChanged(.p2pUnavailable)
        XCTAssertFalse(session.canStartPushToTalk(source: .mouse))
        session.pushToTalkPressed(source: .mouse)
        XCTAssertEqual(session.activity, .p2pUnavailable)

        session.connectionChanged(.listening)
        session.floorGrantReceived(speakerID: UserID("teammate"))
        XCTAssertFalse(session.canStartPushToTalk(source: .mouse))
        session.pushToTalkPressed(source: .mouse)
        XCTAssertEqual(session.activity, .floorBusy)
    }

    func testConnectionAndP2PFailuresSurfaceAsActivityStates() {
        let session = AppSessionState.mockSignedIn()

        session.connectionChanged(.connected)
        XCTAssertEqual(session.activity, .connected)

        session.connectionChanged(.reconnecting)
        XCTAssertEqual(session.activity, .reconnecting)

        session.connectionChanged(.p2pUnavailable)
        XCTAssertEqual(session.activity, .p2pUnavailable)
    }
}
