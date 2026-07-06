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
        XCTAssertFalse(session.shouldPublishMicrophone)

        session.floorGrantReceived(tokenID: FloorTokenID("floor-1"), speakerID: session.localUserID)

        XCTAssertEqual(session.floor, .granted(speakerID: session.localUserID, tokenID: FloorTokenID("floor-1")))
        XCTAssertEqual(session.activity, .speaking)
        XCTAssertTrue(session.shouldPublishMicrophone)

        session.pushToTalkReleased()

        XCTAssertEqual(session.floor, .idle)
        XCTAssertEqual(session.activity, .listening)
        XCTAssertFalse(session.shouldPublishMicrophone)
        XCTAssertEqual(session.lastReleasedFloorTokenID, FloorTokenID("floor-1"))
    }

    func testFloorDeniedReleasedAndReconnectStopPublishingFailClosed() {
        let session = AppSessionState.mockSignedIn()
        session.selectConversation(id: ConversationID("ops"))

        session.pushToTalkPressed(source: .mouse)
        session.floorDeniedReceived(reason: .busy, speakerID: UserID("teammate"))

        XCTAssertEqual(session.floor, .busy(speakerID: UserID("teammate")))
        XCTAssertEqual(session.activity, .floorBusy)
        XCTAssertFalse(session.shouldPublishMicrophone)

        session.floorGrantReceived(tokenID: FloorTokenID("floor-2"), speakerID: session.localUserID)
        XCTAssertFalse(session.shouldPublishMicrophone)

        session.pushToTalkReleased()
        session.pushToTalkPressed(source: .mouse)
        session.floorGrantReceived(tokenID: FloorTokenID("floor-3"), speakerID: session.localUserID)
        XCTAssertTrue(session.shouldPublishMicrophone)

        session.floorReleasedReceived(tokenID: FloorTokenID("floor-3"), reason: .timeout)

        XCTAssertEqual(session.floor, .idle)
        XCTAssertEqual(session.activity, .listening)
        XCTAssertFalse(session.shouldPublishMicrophone)

        session.pushToTalkPressed(source: .mouse)
        session.floorGrantReceived(tokenID: FloorTokenID("floor-4"), speakerID: session.localUserID)
        session.connectionChanged(.reconnecting)

        XCTAssertFalse(session.shouldPublishMicrophone)
        XCTAssertEqual(session.activity, .reconnecting)
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

        session.floorGrantReceived(tokenID: FloorTokenID("floor-remote"), speakerID: UserID("teammate"))

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
        session.floorGrantReceived(tokenID: FloorTokenID("floor-remote"), speakerID: UserID("teammate"))
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
