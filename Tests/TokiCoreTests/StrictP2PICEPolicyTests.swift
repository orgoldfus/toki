import XCTest
@testable import TokiCore

final class StrictP2PICEPolicyTests: XCTestCase {
    func testAcceptsStunOnlyConfigWithDisabledRelayPolicy() throws {
        let config = ICEConfigResponse(
            iceServers: [ICEConfigServer(urls: ["stun:stun.l.google.com:19302"])],
            relayPolicy: .disabled
        )

        XCTAssertNoThrow(try StrictP2PICEPolicy.validate(config))
    }

    func testRejectsTurnUrlsRelayPolicyChangesAndRelayCandidates() {
        XCTAssertThrowsError(
            try StrictP2PICEPolicy.validate(
                ICEConfigResponse(
                    iceServers: [ICEConfigServer(urls: ["turn:relay.example.com:3478"])],
                    relayPolicy: .disabled
                )
            )
        )

        XCTAssertThrowsError(
            try StrictP2PICEPolicy.validate(
                ICEConfigResponse(
                    iceServers: [ICEConfigServer(urls: ["stun:stun.l.google.com:19302"])],
                    relayPolicy: .enabled
                )
            )
        )

        XCTAssertThrowsError(
            try StrictP2PICEPolicy.validateCandidate(
                "candidate:842163049 1 udp 1677729535 203.0.113.10 54400 typ relay raddr 0.0.0.0 rport 0"
            )
        )
    }
}
