import Foundation
#if canImport(ApplicationServices)
import ApplicationServices
#endif
#if canImport(AVFoundation)
import AVFoundation
#endif

public enum PermissionKind: String, Codable, Equatable, Sendable {
    case microphone
    case inputMonitoring
}

public enum PermissionStatus: String, Codable, Equatable, Sendable {
    case notDetermined
    case granted
    case denied
}

public protocol PermissionCoordinating: Sendable {
    var microphonePermission: PermissionStatus { get }
    var inputMonitoringPermission: PermissionStatus { get }
    func requestMicrophonePermission() async -> PermissionStatus
    func refreshInputMonitoringPermission() -> PermissionStatus
}

public final class PermissionCoordinator: PermissionCoordinating, @unchecked Sendable {
    public private(set) var microphonePermission: PermissionStatus
    public private(set) var inputMonitoringPermission: PermissionStatus

    private let microphoneRequester: @Sendable () async -> PermissionStatus
    private let inputMonitoringReader: @Sendable () -> PermissionStatus

    public init(
        microphonePermission: PermissionStatus,
        inputMonitoringPermission: PermissionStatus,
        microphoneRequester: @escaping @Sendable () async -> PermissionStatus = { .notDetermined },
        inputMonitoringReader: @escaping @Sendable () -> PermissionStatus = { .notDetermined }
    ) {
        self.microphonePermission = microphonePermission
        self.inputMonitoringPermission = inputMonitoringPermission
        self.microphoneRequester = microphoneRequester
        self.inputMonitoringReader = inputMonitoringReader
    }

    public static func live(inputMonitoringReader: @escaping @Sendable () -> PermissionStatus = { .notDetermined }) -> PermissionCoordinator {
        let inputReader: @Sendable () -> PermissionStatus = {
            let status = liveInputMonitoringPermission()
            return status == .notDetermined ? inputMonitoringReader() : status
        }

        return PermissionCoordinator(
            microphonePermission: currentMicrophonePermission(),
            inputMonitoringPermission: inputReader(),
            microphoneRequester: { await requestMicrophoneAccess() },
            inputMonitoringReader: inputReader
        )
    }

    public func requestMicrophonePermission() async -> PermissionStatus {
        let status = await microphoneRequester()
        microphonePermission = status
        return status
    }

    public func refreshInputMonitoringPermission() -> PermissionStatus {
        let status = inputMonitoringReader()
        inputMonitoringPermission = status
        return status
    }

    private static func currentMicrophonePermission() -> PermissionStatus {
        #if canImport(AVFoundation)
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return .granted
        case .denied, .restricted:
            return .denied
        case .notDetermined:
            return .notDetermined
        @unknown default:
            return .denied
        }
        #else
        return .notDetermined
        #endif
    }

    private static func requestMicrophoneAccess() async -> PermissionStatus {
        #if canImport(AVFoundation)
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        return granted ? .granted : .denied
        #else
        return .notDetermined
        #endif
    }

    private static func liveInputMonitoringPermission() -> PermissionStatus {
        #if canImport(ApplicationServices)
        return CGPreflightListenEventAccess() ? .granted : .denied
        #else
        return .notDetermined
        #endif
    }
}
