import XCTest
@testable import TokiCore

final class BetaReleaseDiagnosticsTests: XCTestCase {
    func testDiagnosticsExportContainsMetadataOnlyAndRedactsSensitiveValues() throws {
        let export = DiagnosticsExport(
            release: AppReleaseMetadata(version: "0.7.0", buildNumber: "42", updateChannel: .beta),
            macOSVersion: "15.5",
            deviceModel: "MacBookPro18,3",
            permissions: PermissionState(microphone: .granted, inputMonitoring: .denied),
            selectedDevices: DiagnosticsDeviceSnapshot(inputName: "Studio Mic", outputName: "Headphones"),
            realtimeEvents: [
                DiagnosticsEventSummary(
                    category: .realtime,
                    conversationID: ConversationID("conversation-1"),
                    peerID: nil,
                    state: "room.join",
                    failureReason: "token secret-token-forbidden was rejected for alice@example.com"
                ),
                DiagnosticsEventSummary(
                    category: .peerConnection,
                    conversationID: ConversationID("conversation-1"),
                    peerID: UserID("peer-1"),
                    state: "ice.candidate",
                    failureReason: "candidate:842163049 1 udp 1677729535 192.0.2.5 3478 typ relay"
                )
            ],
            errors: [
                "magic link token magic-abc expired",
                "SDP offer v=0\\no=- 46117326 2 IN IP4 127.0.0.1"
            ]
        )

        let data = try JSONEncoder.tokiDiagnostics.encode(export.redacted())
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertTrue(text.contains("\"version\":\"0.7.0\""))
        XCTAssertTrue(text.contains("\"updateChannel\":\"beta\""))
        XCTAssertTrue(text.contains("Studio Mic"))
        XCTAssertFalse(text.contains("secret-token-forbidden"))
        XCTAssertFalse(text.contains("alice@example.com"))
        XCTAssertFalse(text.localizedCaseInsensitiveContains("candidate:"))
        XCTAssertFalse(text.localizedCaseInsensitiveContains("typ relay"))
        XCTAssertFalse(text.localizedCaseInsensitiveContains("v=0"))
        XCTAssertFalse(text.localizedCaseInsensitiveContains("magic-abc"))
    }

    func testPreBetaReleaseGateRequiresSigningNotarizationUpdatesQAAndStrictP2P() {
        let blocked = PreBetaReleaseChecklist(
            signingIdentity: "",
            notarizationResult: .notRun,
            updateFeedURL: nil,
            backendVersion: "api-2026.07.06",
            qaSummary: QAPassFailSummary(passed: 12, failed: 0, blocked: 0),
            strictP2PVerification: StrictP2PReleaseVerification(
                turnDisabled: false,
                serverMediaDisabled: true,
                forbiddenTermsFound: ["turn:"]
            )
        )

        XCTAssertFalse(blocked.isReadyForBeta)
        XCTAssertTrue(blocked.blockingReasons.contains(.missingSigningIdentity))
        XCTAssertTrue(blocked.blockingReasons.contains(.notarizationIncomplete))
        XCTAssertTrue(blocked.blockingReasons.contains(.missingUpdateFeedURL))
        XCTAssertTrue(blocked.blockingReasons.contains(.strictP2PNotVerified))

        let ready = PreBetaReleaseChecklist(
            signingIdentity: "Developer ID Application: Toki",
            notarizationResult: .accepted,
            updateFeedURL: URL(string: "https://updates.example.com/toki/beta/appcast.xml"),
            backendVersion: "api-2026.07.06",
            qaSummary: QAPassFailSummary(passed: 18, failed: 0, blocked: 0),
            strictP2PVerification: StrictP2PReleaseVerification(
                turnDisabled: true,
                serverMediaDisabled: true,
                forbiddenTermsFound: []
            )
        )

        XCTAssertTrue(ready.isReadyForBeta)
        XCTAssertTrue(ready.blockingReasons.isEmpty)
    }

    func testPrivacySafeLogEventRedactsTokensEmailsSDPICEAndAudioPayloads() throws {
        let event = PrivacySafeLogEvent(
            category: .floor,
            name: "floor.request",
            conversationID: ConversationID("conversation-1"),
            userID: UserID("user-1"),
            metadata: [
                "token": "session-token-secret",
                "email": "alice@example.com",
                "sdp": "v=0\\no=- 46117326 2 IN IP4 127.0.0.1",
                "iceCandidate": "candidate:842163049 1 udp 1677729535 192.0.2.5 3478 typ relay",
                "encodedAudio": "base64-audio",
                "state": "requesting"
            ]
        )

        let data = try JSONEncoder.tokiDiagnostics.encode(event.redacted())
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertTrue(text.contains("floor.request"))
        XCTAssertTrue(text.contains("conversation-1"))
        XCTAssertTrue(text.contains("user-1"))
        XCTAssertTrue(text.contains("requesting"))
        XCTAssertFalse(text.contains("session-token-secret"))
        XCTAssertFalse(text.contains("alice@example.com"))
        XCTAssertFalse(text.localizedCaseInsensitiveContains("candidate:"))
        XCTAssertFalse(text.localizedCaseInsensitiveContains("encodedAudio"))
        XCTAssertFalse(text.localizedCaseInsensitiveContains("base64-audio"))
    }
}
