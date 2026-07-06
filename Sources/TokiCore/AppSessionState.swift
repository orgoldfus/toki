import Combine
import Foundation

public enum AuthState: Equatable, Sendable {
    case signedOut
    case signedIn(userID: UserID)
}

public enum RealtimeConnectionState: Equatable, Sendable {
    case disconnected
    case connected
    case listening
    case reconnecting
    case p2pUnavailable
}

public enum FloorBlockReason: Equatable, Sendable {
    case microphoneDenied
    case inputMonitoringDenied
}

public enum FloorState: Equatable, Sendable {
    case idle
    case requesting(localUserID: UserID)
    case granted(speakerID: UserID, tokenID: FloorTokenID)
    case busy(speakerID: UserID)
    case blocked(reason: FloorBlockReason)
}

public enum SessionActivity: Equatable, Sendable {
    case idle
    case connected
    case listening
    case requestingFloor
    case speaking
    case floorBusy
    case reconnecting
    case p2pUnavailable
    case permissionDenied(PermissionKind)
}

public struct PermissionState: Equatable, Sendable {
    public let microphone: PermissionStatus
    public let inputMonitoring: PermissionStatus

    public init(microphone: PermissionStatus, inputMonitoring: PermissionStatus) {
        self.microphone = microphone
        self.inputMonitoring = inputMonitoring
    }
}

public final class AppSessionState: ObservableObject, @unchecked Sendable {
    @Published public private(set) var auth: AuthState
    @Published public private(set) var localUserID: UserID
    @Published public private(set) var activeConversationID: ConversationID?
    @Published public private(set) var realtimeConnection: RealtimeConnectionState
    @Published public private(set) var floor: FloorState
    @Published public private(set) var activity: SessionActivity
    @Published public private(set) var devicePreferences: DevicePreferences
    @Published public private(set) var shouldPublishMicrophone = false
    @Published public private(set) var lastReleasedFloorTokenID: FloorTokenID?
    @Published public private(set) var replayAvailableDuration: TimeInterval = 0
    @Published public private(set) var lastReplayClearReason: ReplayClearReason?

    private let permissions: PermissionCoordinating
    private let replayBuffer: LocalReplayBuffer
    private var isPushToTalkActive = false

    public init(
        localUserID: UserID,
        permissions: PermissionCoordinating,
        realtimeConnection: RealtimeConnectionState = .disconnected,
        floor: FloorState = .idle,
        activity: SessionActivity = .idle,
        devicePreferences: DevicePreferences = .default,
        replayBuffer: LocalReplayBuffer = LocalReplayBuffer()
    ) {
        self.auth = .signedIn(userID: localUserID)
        self.localUserID = localUserID
        self.permissions = permissions
        self.replayBuffer = replayBuffer
        self.realtimeConnection = realtimeConnection
        self.floor = floor
        self.activity = activity
        self.devicePreferences = devicePreferences
    }

    public static func mockSignedIn(
        localUserID: UserID = UserID("local-user"),
        microphone: PermissionStatus = .granted,
        inputMonitoring: PermissionStatus = .granted
    ) -> AppSessionState {
        AppSessionState(
            localUserID: localUserID,
            permissions: PermissionCoordinator(
                microphonePermission: microphone,
                inputMonitoringPermission: inputMonitoring
            )
        )
    }

    public var permissionState: PermissionState {
        PermissionState(
            microphone: permissions.microphonePermission,
            inputMonitoring: permissions.inputMonitoringPermission
        )
    }

    public func updateDevicePreferences(_ preferences: DevicePreferences) {
        devicePreferences = preferences
    }

    public func selectConversation(id: ConversationID) {
        if activeConversationID != nil, activeConversationID != id {
            clearReplay(reason: .roomSwitch)
        }
        activeConversationID = id
        realtimeConnection = .listening
        floor = .idle
        activity = .listening
    }

    public func appendReceivedAudio(_ segment: LocalAudioSegment, conversationID: ConversationID) {
        guard activeConversationID == conversationID else {
            return
        }

        replayBuffer.append(segment: segment)
        replayAvailableDuration = replayBuffer.availableDuration
    }

    public func appendLocalMicrophoneAudioForReplay(duration: TimeInterval) {
        _ = duration
    }

    public func playRecentReplay(duration: TimeInterval) -> [LocalAudioSegment] {
        ReplayPlayer(buffer: replayBuffer).playRecent(duration: duration)
    }

    public func signOut() {
        auth = .signedOut
        activeConversationID = nil
        realtimeConnection = .disconnected
        floor = .idle
        activity = .idle
        shouldPublishMicrophone = false
        isPushToTalkActive = false
        clearReplay(reason: .signOut)
    }

    public func clearReplayForAppTermination() {
        clearReplay(reason: .appTermination)
    }

    public func canStartPushToTalk(source: PushToTalkSource) -> Bool {
        guard activeConversationID != nil else {
            return false
        }

        guard realtimeConnection == .listening else {
            return false
        }

        guard permissions.microphonePermission == .granted else {
            return false
        }

        if source == .keyboard && permissions.inputMonitoringPermission == .denied {
            return false
        }

        guard floor == .idle else {
            return false
        }

        return true
    }

    public func pushToTalkPressed(source: PushToTalkSource) {
        guard activeConversationID != nil else {
            return
        }

        guard permissions.microphonePermission == .granted else {
            isPushToTalkActive = false
            floor = .blocked(reason: .microphoneDenied)
            activity = .permissionDenied(.microphone)
            return
        }

        guard source != .keyboard || permissions.inputMonitoringPermission == .granted else {
            isPushToTalkActive = false
            floor = .blocked(reason: .inputMonitoringDenied)
            activity = .permissionDenied(.inputMonitoring)
            return
        }

        guard realtimeConnection == .listening, floor == .idle else {
            isPushToTalkActive = false
            return
        }

        isPushToTalkActive = true
        shouldPublishMicrophone = false
        lastReleasedFloorTokenID = nil
        floor = .requesting(localUserID: localUserID)
        activity = .requestingFloor
    }

    public func floorGrantReceived(tokenID: FloorTokenID, speakerID: UserID) {
        if speakerID == localUserID && isPushToTalkActive {
            floor = .granted(speakerID: speakerID, tokenID: tokenID)
            activity = .speaking
            shouldPublishMicrophone = true
            return
        }

        shouldPublishMicrophone = false
        floor = .busy(speakerID: speakerID)
        activity = .floorBusy
    }

    public func floorDeniedReceived(reason: FloorDeniedReason, speakerID: UserID? = nil) {
        isPushToTalkActive = false
        shouldPublishMicrophone = false
        switch reason {
        case .busy:
            floor = .busy(speakerID: speakerID ?? localUserID)
            activity = .floorBusy
        case .notJoined, .forbidden:
            floor = .idle
            activity = activeConversationID == nil ? .idle : .listening
        }
    }

    public func floorReleasedReceived(tokenID: FloorTokenID, reason: FloorReleasedReason) {
        _ = tokenID
        _ = reason
        shouldPublishMicrophone = false
        floor = .idle
        activity = activeConversationID == nil ? .idle : .listening
    }

    public func pushToTalkReleased() {
        isPushToTalkActive = false
        if case .granted(let speakerID, let tokenID) = floor, speakerID == localUserID {
            lastReleasedFloorTokenID = tokenID
        }
        shouldPublishMicrophone = false

        guard activeConversationID != nil else {
            floor = .idle
            activity = .idle
            return
        }

        floor = .idle
        activity = .listening
    }

    public func connectionChanged(_ state: RealtimeConnectionState) {
        realtimeConnection = state

        switch state {
        case .disconnected:
            shouldPublishMicrophone = false
            floor = .idle
            activity = .idle
        case .connected:
            shouldPublishMicrophone = false
            activity = .connected
        case .listening:
            activity = activeConversationID == nil ? .idle : .listening
        case .reconnecting:
            shouldPublishMicrophone = false
            floor = .idle
            activity = .reconnecting
        case .p2pUnavailable:
            shouldPublishMicrophone = false
            floor = .idle
            activity = .p2pUnavailable
        }
    }

    private func clearReplay(reason: ReplayClearReason) {
        replayBuffer.clear(reason: reason)
        replayAvailableDuration = replayBuffer.availableDuration
        lastReplayClearReason = replayBuffer.lastClearReason
    }
}
