import AppKit
import Combine
import Foundation
import TokiCore

protocol AppShellAPIService: Sendable {
    func requestMagicLink(email: String) async throws -> MagicLinkResponse
    func createSession(token: String, deviceName: String) async throws -> SessionResponse
    func conversations(sessionToken: String) async throws -> ConversationsResponse
}

struct TokiBackendAppShellAPIService: AppShellAPIService {
    private let client: TokiAPIClient

    init(baseURL: URL = URL(string: "http://127.0.0.1:8080")!) {
        self.client = TokiAPIClient(baseURL: baseURL)
    }

    func requestMagicLink(email: String) async throws -> MagicLinkResponse {
        try await client.requestMagicLink(email: email)
    }

    func createSession(token: String, deviceName: String) async throws -> SessionResponse {
        try await client.createSession(token: token, deviceName: deviceName)
    }

    func conversations(sessionToken: String) async throws -> ConversationsResponse {
        try await client.conversations(sessionToken: sessionToken)
    }
}

@MainActor
final class AppShellModel: ObservableObject {
    enum AuthenticationState: Equatable {
        case signedOut
        case signedIn
    }

    enum PermissionPreset: String, CaseIterable, Identifiable {
        case ready
        case microphoneDenied
        case inputMonitoringDenied

        var id: String { rawValue }

        var title: String {
            switch self {
            case .ready:
                "Ready"
            case .microphoneDenied:
                "Microphone Denied"
            case .inputMonitoringDenied:
                "Shortcut Unavailable"
            }
        }

    }

    enum MenuBarStatus: Equatable {
        case signedOut
        case connected
        case listening
        case requestingFloor
        case speaking
        case floorBusy
        case microphoneBlocked
        case shortcutBlocked
        case reconnecting
        case p2pUnavailable

        var label: String {
            switch self {
            case .signedOut:
                "Signed Out"
            case .connected:
                "Connected"
            case .listening:
                "Listening"
            case .requestingFloor:
                "Requesting"
            case .speaking:
                "Speaking"
            case .floorBusy:
                "Floor Busy"
            case .microphoneBlocked:
                "Mic Blocked"
            case .shortcutBlocked:
                "Shortcut Blocked"
            case .reconnecting:
                "Reconnecting"
            case .p2pUnavailable:
                "P2P Unavailable"
            }
        }

        var symbolName: String {
            switch self {
            case .signedOut:
                "person.crop.circle.badge.xmark"
            case .connected:
                "bolt.horizontal.circle"
            case .listening:
                "waveform.circle"
            case .requestingFloor:
                "hourglass.circle"
            case .speaking:
                "mic.circle.fill"
            case .floorBusy:
                "person.wave.2"
            case .microphoneBlocked:
                "mic.slash.circle"
            case .shortcutBlocked:
                "keyboard.badge.ellipsis"
            case .reconnecting:
                "arrow.triangle.2.circlepath.circle"
            case .p2pUnavailable:
                "wifi.slash"
            }
        }
    }

    struct RoomSummary: Identifiable, Equatable {
        let id: ConversationID
        let title: String
        let subtitle: String
        let participants: Int
    }

    @Published private(set) var authenticationState: AuthenticationState = .signedOut
    @Published private(set) var activeConversationID: ConversationID?
    @Published private(set) var menuBarStatus: MenuBarStatus = .signedOut
    @Published private(set) var activityLabel = "Signed out"
    @Published private(set) var detailStatus = "Select a room to listen."
    @Published private(set) var canUseManualPTT = false
    @Published private(set) var canUseKeyboardPTT = false
    @Published private(set) var rooms: [RoomSummary] = []
    @Published var signInEmail = ""
    @Published private(set) var signInError: String?
    @Published var isOutputMuted = false
    @Published var permissionPreset: PermissionPreset = .ready {
        didSet { rebuildSessionForPermissions() }
    }
    @Published var launchAtLogin = false
    @Published var diagnosticsOptIn = false
    @Published var selectedInputDeviceID = "input-built-in"
    @Published var selectedOutputDeviceID = "output-system"
    @Published var pushToTalkShortcutLabel = "Shift + Command + Space"

    private let apiService: AppShellAPIService
    private let sessionTokenStore: SessionTokenStoring
    private let settingsStore = LocalSettingsStore(defaults: .standard)
    private let permissionCoordinator: PermissionCoordinating
    private var currentUserID = UserID("local-user")
    private var session: AppSessionState?
    private var delayedGrantTask: Task<Void, Never>?
    private var isShortcutHeld = false

    init(
        apiService: AppShellAPIService = TokiBackendAppShellAPIService(),
        sessionTokenStore: SessionTokenStoring = KeychainSessionTokenStore(),
        permissionCoordinator: PermissionCoordinating = PermissionCoordinator.live()
    ) {
        self.apiService = apiService
        self.sessionTokenStore = sessionTokenStore
        self.permissionCoordinator = permissionCoordinator
        loadSettings()
    }

    var selectedRoom: RoomSummary? {
        guard let activeConversationID else { return nil }
        return rooms.first { $0.id == activeConversationID }
    }

    func signIn() async {
        let email = signInEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !email.isEmpty else {
            signInError = "Enter an invited email."
            return
        }

        do {
            signInError = nil
            let magicLink = try await apiService.requestMagicLink(email: email)
            let sessionResponse = try await apiService.createSession(
                token: magicLink.token,
                deviceName: Host.current().localizedName ?? "Mac"
            )
            try sessionTokenStore.saveToken(sessionResponse.sessionToken)
            let conversationsResponse = try await apiService.conversations(sessionToken: sessionResponse.sessionToken)

            currentUserID = sessionResponse.user.id
            rooms = conversationsResponse.conversations.map { RoomSummary(conversation: $0, currentUserID: currentUserID) }
            authenticationState = .signedIn
            rebuildSessionForPermissions()
            if let firstRoom = rooms.first {
                selectRoom(firstRoom.id)
            }
        } catch {
            try? sessionTokenStore.clearToken()
            authenticationState = .signedOut
            rooms = []
            signInError = "Sign in failed. Confirm the invite and backend connection."
        }
    }

    func signOut() {
        delayedGrantTask?.cancel()
        try? sessionTokenStore.clearToken()
        session = nil
        authenticationState = .signedOut
        activeConversationID = nil
        rooms = []
        menuBarStatus = .signedOut
        activityLabel = "Signed out"
        detailStatus = "Open Toki to join a room."
        canUseManualPTT = false
        canUseKeyboardPTT = false
    }

    func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first?.makeKeyAndOrderFront(nil)
    }

    func selectRoom(_ conversationID: ConversationID) {
        guard let session else { return }
        session.selectConversation(id: conversationID)
        activeConversationID = conversationID
        syncFromSession()
    }

    func startManualPushToTalk() {
        guard let session else { return }
        session.pushToTalkPressed(source: .mouse)
        syncFromSession()
        scheduleFloorGrantForCurrentUser(usingKeyboardSource: false)
    }

    func startShortcutPushToTalk() {
        guard let session else { return }
        session.pushToTalkPressed(source: .keyboard)
        syncFromSession()
        scheduleFloorGrantForCurrentUser(usingKeyboardSource: true)
    }

    @discardableResult
    func handleShortcutPressed() -> Bool {
        guard !isShortcutHeld, canUseKeyboardPTT else {
            return false
        }

        isShortcutHeld = true
        startShortcutPushToTalk()
        return true
    }

    func handleShortcutReleased() {
        guard isShortcutHeld else {
            return
        }

        isShortcutHeld = false
        stopPushToTalk()
    }

    func stopPushToTalk() {
        delayedGrantTask?.cancel()
        session?.pushToTalkReleased()
        syncFromSession()
    }

    func requestMicrophonePermission() async {
        let status = await permissionCoordinator.requestMicrophonePermission()
        permissionPreset = status == .denied ? .microphoneDenied : .ready
        rebuildSessionForPermissions()
    }

    func refreshInputMonitoringPermission() {
        let status = permissionCoordinator.refreshInputMonitoringPermission()
        permissionPreset = status == .denied ? .inputMonitoringDenied : .ready
        rebuildSessionForPermissions()
    }

    func simulateReconnect() {
        session?.connectionChanged(.reconnecting)
        syncFromSession()
    }

    func simulateP2PUnavailable() {
        session?.connectionChanged(.p2pUnavailable)
        syncFromSession()
    }

    func restoreConnectedState() {
        session?.connectionChanged(.listening)
        syncFromSession()
    }

    func simulateRemoteSpeaker() {
        guard let session else { return }
        session.floorGrantReceived(speakerID: UserID("teammate"))
        syncFromSession()
    }

    func saveSettings() {
        let preferences = DevicePreferences(
            selectedInputDeviceID: selectedInputDeviceID,
            selectedOutputDeviceID: selectedOutputDeviceID,
            pushToTalkShortcut: PushToTalkShortcut(keyCode: 49, modifiers: [.command, .shift]),
            launchAtLogin: launchAtLogin,
            diagnosticsOptIn: diagnosticsOptIn
        )

        settingsStore.save(preferences)
    }

    private func rebuildSessionForPermissions() {
        guard authenticationState == .signedIn else { return }

        delayedGrantTask?.cancel()
        isShortcutHeld = false
        let session: AppSessionState
        switch permissionPreset {
        case .ready:
            session = AppSessionState.mockSignedIn(
                localUserID: currentUserID,
                microphone: .granted,
                inputMonitoring: .granted
            )
        case .microphoneDenied:
            session = AppSessionState.mockSignedIn(
                localUserID: currentUserID,
                microphone: .denied,
                inputMonitoring: .granted
            )
        case .inputMonitoringDenied:
            session = AppSessionState.mockSignedIn(
                localUserID: currentUserID,
                microphone: .granted,
                inputMonitoring: .denied
            )
        }
        self.session = session

        if let activeConversationID {
            session.selectConversation(id: activeConversationID)
        }

        syncFromSession()
    }

    private func scheduleFloorGrantForCurrentUser(usingKeyboardSource: Bool) {
        guard let session else { return }
        delayedGrantTask?.cancel()
        delayedGrantTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard let self, !Task.isCancelled else {
                return
            }

            let canStart =
                if usingKeyboardSource {
                    self.session?.canStartPushToTalk(source: .keyboard) == true
                } else {
                    self.session?.canStartPushToTalk(source: .mouse) == true
                }

            guard canStart else {
                return
            }

            self.session?.floorGrantReceived(speakerID: session.localUserID)
            self.syncFromSession()
        }
    }

    private func syncFromSession() {
        guard let session else { return }

        canUseManualPTT = session.canStartPushToTalk(source: .mouse)
        canUseKeyboardPTT = session.canStartPushToTalk(source: .keyboard)
        menuBarStatus = resolveMenuBarStatus(session: session)
        activityLabel = resolveActivityLabel(session: session)
        detailStatus = resolveDetailStatus(session: session)
    }

    private func resolveMenuBarStatus(session: AppSessionState) -> MenuBarStatus {
        switch session.activity {
        case .idle, .connected:
            .connected
        case .speaking:
            .speaking
        case .reconnecting:
            .reconnecting
        case .p2pUnavailable:
            .p2pUnavailable
        case .listening:
            .listening
        case .requestingFloor:
            .requestingFloor
        case .floorBusy:
            .floorBusy
        case .permissionDenied(.microphone):
            .microphoneBlocked
        case .permissionDenied(.inputMonitoring):
            .shortcutBlocked
        @unknown default:
            .connected
        }
    }

    private func resolveActivityLabel(session: AppSessionState) -> String {
        switch session.activity {
        case .idle:
            "Connected"
        case .connected:
            "Connected"
        case .listening:
            "Listening"
        case .requestingFloor:
            "Requesting floor"
        case .speaking:
            "Speaking"
        case .floorBusy:
            "Floor busy"
        case .reconnecting:
            "Reconnecting"
        case .p2pUnavailable:
            "P2P unavailable"
        case .permissionDenied(.microphone):
            "Microphone permission required"
        case .permissionDenied(_):
            "Shortcut permission required"
        @unknown default:
            "Connected"
        }
    }

    private func resolveDetailStatus(session: AppSessionState) -> String {
        switch session.activity {
        case .idle:
            "Join a room to start listening."
        case .connected:
            "Select a room to start listening."
        case .listening:
            "Ready to listen in the active room."
        case .requestingFloor:
            "Waiting for the floor token."
        case .speaking:
            "PTT is held. Release to stop transmitting."
        case .floorBusy:
            "Another teammate has the floor."
        case .reconnecting:
            "Realtime link dropped. Rejoin the room when connected."
        case .p2pUnavailable:
            "Direct peer path is unavailable. Toki will not transmit."
        case .permissionDenied(.microphone):
            "Microphone access is required before PTT can start."
        case .permissionDenied(_):
            "Global shortcut access is unavailable. Manual PTT still works."
        @unknown default:
            "Connected."
        }
    }

    private func loadSettings() {
        guard let preferences = settingsStore.load() else { return }

        selectedInputDeviceID = preferences.selectedInputDeviceID ?? selectedInputDeviceID
        selectedOutputDeviceID = preferences.selectedOutputDeviceID ?? selectedOutputDeviceID
        launchAtLogin = preferences.launchAtLogin
        diagnosticsOptIn = preferences.diagnosticsOptIn

        if let shortcut = preferences.pushToTalkShortcut, shortcut.keyCode == 49, shortcut.modifiers == [.command, .shift] {
            pushToTalkShortcutLabel = "Shift + Command + Space"
        }
    }
}

private extension AppShellModel.RoomSummary {
    init(conversation: ConversationSummary, currentUserID: UserID) {
        let title = conversation.displayName ?? conversation.members
            .first { $0.user.id != currentUserID }?
            .user
            .displayName ?? "Direct Conversation"
        let memberCount = conversation.members.count
        let noun = memberCount == 1 ? "member" : "members"

        self.init(
            id: conversation.id,
            title: title,
            subtitle: "\(memberCount) \(noun)",
            participants: memberCount
        )
    }
}
