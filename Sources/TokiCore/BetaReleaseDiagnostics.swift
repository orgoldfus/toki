import Foundation

public enum UpdateChannel: String, Codable, Equatable, Sendable {
    case beta
    case stable

    public var label: String {
        switch self {
        case .beta:
            "Beta"
        case .stable:
            "Stable"
        }
    }
}

public struct AppReleaseMetadata: Codable, Equatable, Sendable {
    public let version: String
    public let buildNumber: String
    public let updateChannel: UpdateChannel

    public init(version: String, buildNumber: String, updateChannel: UpdateChannel) {
        self.version = version
        self.buildNumber = buildNumber
        self.updateChannel = updateChannel
    }

    public static let betaPlaceholder = AppReleaseMetadata(
        version: "0.7.0",
        buildNumber: "0",
        updateChannel: .beta
    )

    public static func current(bundle: Bundle = .main, updateChannel: UpdateChannel = .beta) -> AppReleaseMetadata {
        AppReleaseMetadata(
            version: bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? betaPlaceholder.version,
            buildNumber: bundle.infoDictionary?["CFBundleVersion"] as? String ?? betaPlaceholder.buildNumber,
            updateChannel: updateChannel
        )
    }
}

public struct DiagnosticsDeviceSnapshot: Codable, Equatable, Sendable {
    public let inputName: String?
    public let outputName: String?

    public init(inputName: String?, outputName: String?) {
        self.inputName = inputName
        self.outputName = outputName
    }
}

public enum DiagnosticsEventCategory: String, Codable, Equatable, Sendable {
    case auth
    case realtime
    case room
    case floor
    case peerConnection
    case permission
    case deviceFallback
}

public struct DiagnosticsEventSummary: Codable, Equatable, Sendable {
    public let category: DiagnosticsEventCategory
    public let conversationID: ConversationID?
    public let peerID: UserID?
    public let state: String
    public let failureReason: String?

    public init(
        category: DiagnosticsEventCategory,
        conversationID: ConversationID?,
        peerID: UserID?,
        state: String,
        failureReason: String? = nil
    ) {
        self.category = category
        self.conversationID = conversationID
        self.peerID = peerID
        self.state = state
        self.failureReason = failureReason
    }

    public func redacted() -> DiagnosticsEventSummary {
        DiagnosticsEventSummary(
            category: category,
            conversationID: conversationID,
            peerID: peerID,
            state: PrivacyRedactor.redactFreeText(state),
            failureReason: failureReason.map(PrivacyRedactor.redactFreeText)
        )
    }

    private enum CodingKeys: String, CodingKey {
        case category
        case conversationID = "conversationId"
        case peerID = "peerId"
        case state
        case failureReason
    }
}

public struct DiagnosticsExport: Codable, Equatable, Sendable {
    public let release: AppReleaseMetadata
    public let macOSVersion: String
    public let deviceModel: String
    public let permissions: PermissionState
    public let selectedDevices: DiagnosticsDeviceSnapshot
    public let realtimeEvents: [DiagnosticsEventSummary]
    public let errors: [String]

    public init(
        release: AppReleaseMetadata,
        macOSVersion: String,
        deviceModel: String,
        permissions: PermissionState,
        selectedDevices: DiagnosticsDeviceSnapshot,
        realtimeEvents: [DiagnosticsEventSummary],
        errors: [String]
    ) {
        self.release = release
        self.macOSVersion = macOSVersion
        self.deviceModel = deviceModel
        self.permissions = permissions
        self.selectedDevices = selectedDevices
        self.realtimeEvents = realtimeEvents
        self.errors = errors
    }

    public func redacted() -> DiagnosticsExport {
        DiagnosticsExport(
            release: release,
            macOSVersion: PrivacyRedactor.redactFreeText(macOSVersion),
            deviceModel: PrivacyRedactor.redactFreeText(deviceModel),
            permissions: permissions,
            selectedDevices: selectedDevices,
            realtimeEvents: realtimeEvents.map { $0.redacted() },
            errors: errors.map(PrivacyRedactor.redactFreeText)
        )
    }
}

public struct PrivacySafeLogEvent: Codable, Equatable, Sendable {
    public let category: DiagnosticsEventCategory
    public let name: String
    public let conversationID: ConversationID?
    public let userID: UserID?
    public let metadata: [String: String]

    public init(
        category: DiagnosticsEventCategory,
        name: String,
        conversationID: ConversationID?,
        userID: UserID?,
        metadata: [String: String]
    ) {
        self.category = category
        self.name = name
        self.conversationID = conversationID
        self.userID = userID
        self.metadata = metadata
    }

    public func redacted() -> PrivacySafeLogEvent {
        PrivacySafeLogEvent(
            category: category,
            name: PrivacyRedactor.redactFreeText(name),
            conversationID: conversationID,
            userID: userID,
            metadata: PrivacyRedactor.redactMetadata(metadata)
        )
    }

    private enum CodingKeys: String, CodingKey {
        case category
        case name
        case conversationID = "conversationId"
        case userID = "userId"
        case metadata
    }
}

public enum NotarizationResult: String, Codable, Equatable, Sendable {
    case notRun
    case accepted
    case rejected
}

public struct QAPassFailSummary: Codable, Equatable, Sendable {
    public let passed: Int
    public let failed: Int
    public let blocked: Int

    public init(passed: Int, failed: Int, blocked: Int) {
        self.passed = passed
        self.failed = failed
        self.blocked = blocked
    }

    public var isPassing: Bool {
        passed > 0 && failed == 0 && blocked == 0
    }
}

public struct StrictP2PReleaseVerification: Codable, Equatable, Sendable {
    public let turnDisabled: Bool
    public let serverMediaDisabled: Bool
    public let forbiddenTermsFound: [String]

    public init(turnDisabled: Bool, serverMediaDisabled: Bool, forbiddenTermsFound: [String]) {
        self.turnDisabled = turnDisabled
        self.serverMediaDisabled = serverMediaDisabled
        self.forbiddenTermsFound = forbiddenTermsFound
    }

    public var isVerified: Bool {
        turnDisabled && serverMediaDisabled && forbiddenTermsFound.isEmpty
    }
}

public enum PreBetaBlockingReason: String, Codable, Equatable, Sendable {
    case missingSigningIdentity
    case notarizationIncomplete
    case missingUpdateFeedURL
    case missingBackendVersion
    case qaIncomplete
    case strictP2PNotVerified
}

public struct PreBetaReleaseChecklist: Codable, Equatable, Sendable {
    public let signingIdentity: String
    public let notarizationResult: NotarizationResult
    public let updateFeedURL: URL?
    public let backendVersion: String
    public let qaSummary: QAPassFailSummary
    public let strictP2PVerification: StrictP2PReleaseVerification

    public init(
        signingIdentity: String,
        notarizationResult: NotarizationResult,
        updateFeedURL: URL?,
        backendVersion: String,
        qaSummary: QAPassFailSummary,
        strictP2PVerification: StrictP2PReleaseVerification
    ) {
        self.signingIdentity = signingIdentity
        self.notarizationResult = notarizationResult
        self.updateFeedURL = updateFeedURL
        self.backendVersion = backendVersion
        self.qaSummary = qaSummary
        self.strictP2PVerification = strictP2PVerification
    }

    public var isReadyForBeta: Bool {
        blockingReasons.isEmpty
    }

    public var blockingReasons: [PreBetaBlockingReason] {
        var reasons: [PreBetaBlockingReason] = []
        if signingIdentity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            reasons.append(.missingSigningIdentity)
        }
        if notarizationResult != .accepted {
            reasons.append(.notarizationIncomplete)
        }
        if updateFeedURL == nil {
            reasons.append(.missingUpdateFeedURL)
        }
        if backendVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            reasons.append(.missingBackendVersion)
        }
        if !qaSummary.isPassing {
            reasons.append(.qaIncomplete)
        }
        if !strictP2PVerification.isVerified {
            reasons.append(.strictP2PNotVerified)
        }
        return reasons
    }
}

public extension JSONEncoder {
    static var tokiDiagnostics: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

enum PrivacyRedactor {
    static func redactMetadata(_ metadata: [String: String]) -> [String: String] {
        metadata.reduce(into: [:]) { output, pair in
            guard !isSensitiveKey(pair.key) else { return }
            output[pair.key] = redactFreeText(pair.value)
        }
    }

    static func redactFreeText(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }
        let lowercased = trimmed.lowercased()
        let sensitiveMarkers = [
            "@",
            "token",
            "magic-link",
            "candidate:",
            "typ relay",
            "sdp",
            "v=0",
            "encodedaudio",
            "audio",
            "replay"
        ]

        if sensitiveMarkers.contains(where: lowercased.contains) {
            return "[redacted]"
        }

        return trimmed
    }

    private static func isSensitiveKey(_ key: String) -> Bool {
        let lowercased = key.lowercased()
        return [
            "token",
            "email",
            "sdp",
            "ice",
            "candidate",
            "audio",
            "replay"
        ].contains { lowercased.contains($0) }
    }
}
