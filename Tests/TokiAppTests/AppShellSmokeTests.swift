import SwiftUI
import TokiCore
import XCTest
@testable import TokiApp

@MainActor
final class AppShellSmokeTests: XCTestCase {
    func testBackendSignInStoresSessionTokenAndLoadsConversations() async throws {
        let tokenStore = InMemorySessionTokenStore()
        let model = AppShellModel(
            apiService: FakeAppShellAPIService(),
            sessionTokenStore: tokenStore
        )

        model.signInEmail = "alice@example.com"
        await model.signIn()

        XCTAssertEqual(model.authenticationState, .signedIn)
        XCTAssertEqual(try tokenStore.loadToken(), "session-token")
        XCTAssertEqual(model.rooms.map(\.title), ["Design"])
        XCTAssertEqual(model.activeConversationID, ConversationID("conversation-1"))
        XCTAssertEqual(model.menuBarStatus, .listening)
        XCTAssertTrue(model.canUseManualPTT)
    }

    func testSignOutClearsStoredSessionToken() async throws {
        let tokenStore = InMemorySessionTokenStore()
        let model = AppShellModel(
            apiService: FakeAppShellAPIService(),
            sessionTokenStore: tokenStore
        )

        model.signInEmail = "alice@example.com"
        await model.signIn()
        model.signOut()

        XCTAssertNil(try tokenStore.loadToken())
        XCTAssertEqual(model.authenticationState, .signedOut)
        XCTAssertTrue(model.rooms.isEmpty)
    }

    func testReplayStateClearsOnRoomSwitchAndSignOut() async throws {
        let tokenStore = InMemorySessionTokenStore()
        let model = AppShellModel(
            apiService: TwoRoomAppShellAPIService(),
            sessionTokenStore: tokenStore
        )
        model.signInEmail = "alice@example.com"
        await model.signIn()

        model.simulateReceivedRemoteAudio(duration: 12, speakerID: UserID("teammate"))

        XCTAssertEqual(model.replayAvailableDurationLabel, "0:12")
        XCTAssertTrue(model.canPlayReplay)

        model.selectRoom(ConversationID("conversation-2"))

        XCTAssertEqual(model.replayAvailableDurationLabel, "0:00")
        XCTAssertFalse(model.canPlayReplay)

        model.simulateReceivedRemoteAudio(duration: 8, speakerID: UserID("teammate"))
        model.applicationWillTerminate()

        XCTAssertEqual(model.replayAvailableDurationLabel, "0:00")
        XCTAssertFalse(model.canPlayReplay)

        model.simulateReceivedRemoteAudio(duration: 8, speakerID: UserID("teammate"))
        model.signOut()

        XCTAssertEqual(model.replayAvailableDurationLabel, "0:00")
        XCTAssertFalse(model.canPlayReplay)
    }

    func testReplayPlaybackDoesNotChangeFloorOrPublishingState() async {
        let model = AppShellModel(apiService: FakeAppShellAPIService())
        model.signInEmail = "alice@example.com"
        await model.signIn()
        model.simulateReceivedRemoteAudio(duration: 12, speakerID: UserID("teammate"))

        model.playRecentReplay()

        XCTAssertEqual(model.menuBarStatus, .listening)
        XCTAssertFalse(model.isReplayPublishingMicrophone)
        XCTAssertFalse(model.isReplayRequestingFloor)
    }

    func testAudioDeviceSelectionsAndMicTestStateAreExposedToSettings() {
        let settingsStore = InMemorySettingsStore()
        let model = AppShellModel(
            apiService: FakeAppShellAPIService(),
            settingsStore: settingsStore,
            audioDeviceProvider: FixedAudioDeviceProvider(
                inputDevices: [
                    AudioDevice(id: "input-built-in", name: "Built-in Microphone", isSystemDefault: true),
                    AudioDevice(id: "input-usb", name: "USB Microphone", isSystemDefault: false)
                ],
                outputDevices: [
                    AudioDevice(id: "output-system", name: "System Output", isSystemDefault: true),
                    AudioDevice(id: "output-headphones", name: "Headphones", isSystemDefault: false)
                ]
            )
        )

        model.selectInputDevice(id: "input-usb")
        model.selectOutputDevice(id: "output-headphones")
        model.startMicTest()
        model.simulateMicInput(samples: [0, 0.6])

        XCTAssertEqual(model.availableInputDevices.map(\.id), ["input-built-in", "input-usb"])
        XCTAssertEqual(model.availableOutputDevices.map(\.id), ["output-system", "output-headphones"])
        XCTAssertEqual(model.selectedInputDeviceID, "input-usb")
        XCTAssertEqual(model.selectedOutputDeviceID, "output-headphones")
        XCTAssertEqual(model.inputLevel, 0.6, accuracy: 0.001)
        XCTAssertFalse(model.micTestPublishesAudio)
        XCTAssertEqual(settingsStore.savedPreferences?.selectedInputDeviceID, "input-usb")
    }

    func testFailedConversationLoadClearsStoredSessionToken() async throws {
        let tokenStore = InMemorySessionTokenStore()
        let model = AppShellModel(
            apiService: FailingConversationAPIService(),
            sessionTokenStore: tokenStore
        )

        model.signInEmail = "alice@example.com"
        await model.signIn()

        XCTAssertNil(try tokenStore.loadToken())
        XCTAssertEqual(model.authenticationState, .signedOut)
        XCTAssertTrue(model.rooms.isEmpty)
    }

    func testMicrophoneDeniedDisablesManualPTTAndShowsRecoveryState() async {
        let model = AppShellModel(apiService: FakeAppShellAPIService())
        model.permissionPreset = .microphoneDenied
        model.signInEmail = "alice@example.com"
        await model.signIn()

        model.startManualPushToTalk()

        XCTAssertFalse(model.canUseManualPTT)
        XCTAssertEqual(model.activityLabel, "Microphone permission required")
    }

    func testMenuStatusReflectsRequestingBusyAndPermissionStates() async {
        let model = AppShellModel(apiService: FakeAppShellAPIService())
        model.signInEmail = "alice@example.com"
        await model.signIn()

        model.startManualPushToTalk()
        XCTAssertEqual(model.menuBarStatus, .requestingFloor)

        model.stopPushToTalk()
        model.simulateRemoteSpeaker()
        XCTAssertEqual(model.menuBarStatus, .floorBusy)
        XCTAssertEqual(model.activeSpeakerLabel, "teammate")
        XCTAssertEqual(model.detailStatus, "teammate has the floor.")

        model.permissionPreset = .microphoneDenied
        model.startManualPushToTalk()
        XCTAssertEqual(model.menuBarStatus, .microphoneBlocked)
    }

    func testShortcutPressIsEdgeTriggeredUntilRelease() async {
        let model = AppShellModel(apiService: FakeAppShellAPIService())
        model.signInEmail = "alice@example.com"
        await model.signIn()

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

private struct FakeAppShellAPIService: AppShellAPIService {
    func requestMagicLink(email: String) async throws -> MagicLinkResponse {
        XCTAssertEqual(email, "alice@example.com")
        return MagicLinkResponse(token: "magic-token")
    }

    func createSession(token: String, deviceName: String) async throws -> SessionResponse {
        XCTAssertEqual(token, "magic-token")
        XCTAssertFalse(deviceName.isEmpty)
        return SessionResponse(
            sessionToken: "session-token",
            user: TokiUserSummary(id: UserID("user-1"), email: "alice@example.com", displayName: "Alice"),
            teamMemberships: [
                TokiTeamMembershipSummary(
                    id: MembershipID("membership-1"),
                    team: TokiTeamSummary(id: TeamID("team-1"), displayName: "Toki Beta"),
                    role: "member"
                )
            ],
            device: TokiDeviceSummary(id: DeviceID("device-1"), name: "Alice Mac")
        )
    }

    func conversations(sessionToken: String) async throws -> ConversationsResponse {
        XCTAssertEqual(sessionToken, "session-token")
        return ConversationsResponse(conversations: [
            ConversationSummary(
                id: ConversationID("conversation-1"),
                type: .group,
                displayName: "Design",
                members: [
                    ConversationMemberSummary(
                        user: TokiUserSummary(id: UserID("user-1"), email: "alice@example.com", displayName: "Alice"),
                        role: "member"
                    )
                ],
                lastPresence: ConversationPresenceSummary(onlineUserIDs: [UserID("user-1")], activeSpeakerID: nil)
            )
        ])
    }
}

private struct FailingConversationAPIService: AppShellAPIService {
    func requestMagicLink(email: String) async throws -> MagicLinkResponse {
        MagicLinkResponse(token: "magic-token")
    }

    func createSession(token: String, deviceName: String) async throws -> SessionResponse {
        SessionResponse(
            sessionToken: "session-token",
            user: TokiUserSummary(id: UserID("user-1"), email: "alice@example.com", displayName: "Alice"),
            teamMemberships: [],
            device: TokiDeviceSummary(id: DeviceID("device-1"), name: "Alice Mac")
        )
    }

    func conversations(sessionToken: String) async throws -> ConversationsResponse {
        throw URLError(.cannotConnectToHost)
    }
}

private struct TwoRoomAppShellAPIService: AppShellAPIService {
    func requestMagicLink(email: String) async throws -> MagicLinkResponse {
        MagicLinkResponse(token: "magic-token")
    }

    func createSession(token: String, deviceName: String) async throws -> SessionResponse {
        SessionResponse(
            sessionToken: "session-token",
            user: TokiUserSummary(id: UserID("user-1"), email: "alice@example.com", displayName: "Alice"),
            teamMemberships: [],
            device: TokiDeviceSummary(id: DeviceID("device-1"), name: "Alice Mac")
        )
    }

    func conversations(sessionToken: String) async throws -> ConversationsResponse {
        ConversationsResponse(conversations: [
            ConversationSummary(
                id: ConversationID("conversation-1"),
                type: .group,
                displayName: "Design",
                members: [
                    ConversationMemberSummary(
                        user: TokiUserSummary(id: UserID("user-1"), email: "alice@example.com", displayName: "Alice"),
                        role: "member"
                    )
                ],
                lastPresence: ConversationPresenceSummary(onlineUserIDs: [UserID("user-1")], activeSpeakerID: nil)
            ),
            ConversationSummary(
                id: ConversationID("conversation-2"),
                type: .group,
                displayName: "Ops",
                members: [
                    ConversationMemberSummary(
                        user: TokiUserSummary(id: UserID("user-1"), email: "alice@example.com", displayName: "Alice"),
                        role: "member"
                    )
                ],
                lastPresence: ConversationPresenceSummary(onlineUserIDs: [UserID("user-1")], activeSpeakerID: nil)
            )
        ])
    }
}

private struct FixedAudioDeviceProvider: AudioDeviceProviding {
    let inputDevices: [AudioDevice]
    let outputDevices: [AudioDevice]

    func availableInputDevices() -> [AudioDevice] {
        inputDevices
    }

    func availableOutputDevices() -> [AudioDevice] {
        outputDevices
    }
}

private final class InMemorySettingsStore: SettingsStoring, @unchecked Sendable {
    private(set) var savedPreferences: DevicePreferences?

    func load() -> DevicePreferences? {
        savedPreferences
    }

    func save(_ preferences: DevicePreferences) {
        savedPreferences = preferences
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
