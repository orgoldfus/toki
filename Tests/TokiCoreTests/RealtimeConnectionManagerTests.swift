import XCTest
@testable import TokiCore

final class RealtimeConnectionManagerTests: XCTestCase {
    func testEventEnvelopeEncodesVersionedMetadataAndPayload() throws {
        let envelope = RealtimeEventEnvelope(
            type: .roomJoin,
            id: "event-1",
            conversationID: ConversationID("conversation-1"),
            sentAt: Date(timeIntervalSince1970: 1_720_000_000),
            payload: RoomJoinPayload(active: true)
        )

        let data = try JSONEncoder.tokiRealtime.encode(envelope)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(object["type"] as? String, "room.join")
        XCTAssertEqual(object["id"] as? String, "event-1")
        XCTAssertEqual(object["conversationId"] as? String, "conversation-1")
        XCTAssertNotNil(object["sentAt"] as? String)
        XCTAssertEqual((object["payload"] as? [String: Any])?["active"] as? Bool, true)
    }

    func testReconnectReauthenticatesRejoinsActiveRoomAndRequestsPeerRenegotiation() async throws {
        let transport = RecordingRealtimeTransport()
        let manager = RealtimeConnectionManager(
            sessionToken: "session-token",
            transport: transport,
            eventID: IncrementingRealtimeEventID(prefix: "test"),
            clock: FixedRealtimeClock(now: Date(timeIntervalSince1970: 1_720_000_000))
        )

        try await manager.connect()
        try await manager.joinActiveRoom(ConversationID("conversation-1"))
        await manager.handleConnectionDropped()

        XCTAssertEqual(manager.state, .reconnecting(attempt: 1))
        XCTAssertEqual(manager.nextReconnectDelay(), .seconds(1))

        try await manager.reconnectNow()

        XCTAssertEqual(transport.connectedTokens, ["session-token", "session-token"])
        XCTAssertEqual(manager.state, .listening(conversationID: ConversationID("conversation-1")))
        XCTAssertTrue(manager.needsPeerRenegotiation)
        XCTAssertEqual(transport.sent.map(\.type), [.roomJoin, .roomJoin])
        XCTAssertEqual(transport.sent.map(\.conversationID), [ConversationID("conversation-1"), ConversationID("conversation-1")])
    }

    func testReconnectBackoffDoublesAndCaps() async {
        let manager = RealtimeConnectionManager(
            sessionToken: "session-token",
            transport: RecordingRealtimeTransport(),
            backoff: RealtimeBackoff(initial: .seconds(1), maximum: .seconds(8))
        )

        await manager.handleConnectionDropped()
        XCTAssertEqual(manager.nextReconnectDelay(), .seconds(1))

        await manager.handleConnectionDropped()
        XCTAssertEqual(manager.nextReconnectDelay(), .seconds(2))

        await manager.handleConnectionDropped()
        await manager.handleConnectionDropped()
        await manager.handleConnectionDropped()
        XCTAssertEqual(manager.nextReconnectDelay(), .seconds(8))
    }
}

private final class RecordingRealtimeTransport: RealtimeTransporting, @unchecked Sendable {
    private(set) var connectedTokens: [String] = []
    private(set) var sent: [AnyRealtimeEventEnvelope] = []

    func connect(sessionToken: String) async throws {
        connectedTokens.append(sessionToken)
    }

    func send(_ envelope: AnyRealtimeEventEnvelope) async throws {
        sent.append(envelope)
    }

    func close() async {}
}
