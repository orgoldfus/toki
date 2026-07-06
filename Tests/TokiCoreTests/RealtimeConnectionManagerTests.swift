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

    func testFloorRequestAndReleaseEventsCarryDeviceAndTokenIDs() async throws {
        let transport = RecordingRealtimeTransport()
        let manager = RealtimeConnectionManager(
            sessionToken: "session-token",
            transport: transport,
            eventID: IncrementingRealtimeEventID(prefix: "floor"),
            clock: FixedRealtimeClock(now: Date(timeIntervalSince1970: 1_720_000_000))
        )

        try await manager.requestFloor(conversationID: ConversationID("conversation-1"), deviceID: DeviceID("device-a"))
        try await manager.releaseFloor(conversationID: ConversationID("conversation-1"), tokenID: FloorTokenID("token-a"))

        XCTAssertEqual(transport.sent.map(\.type), [.floorRequest, .floorRelease])
        XCTAssertEqual(transport.sent.map(\.conversationID), [ConversationID("conversation-1"), ConversationID("conversation-1")])
        XCTAssertEqual(transport.sent[0].payload.objectValue?["conversationId"], .string("conversation-1"))
        XCTAssertEqual(transport.sent[0].payload.objectValue?["deviceId"], .string("device-a"))
        XCTAssertEqual(transport.sent[1].payload.objectValue?["conversationId"], .string("conversation-1"))
        XCTAssertEqual(transport.sent[1].payload.objectValue?["tokenId"], .string("token-a"))
    }

    func testFloorGrantPayloadDecodesServerFields() throws {
        let data = Data(
            """
            {
              "conversationId": "conversation-1",
              "tokenId": "token-a",
              "speakerUserId": "user-a",
              "speakerDeviceId": "device-a",
              "grantedAt": "2026-07-06T10:00:00Z"
            }
            """.utf8
        )

        let payload = try JSONDecoder.tokiRealtime.decode(FloorGrantedPayload.self, from: data)

        XCTAssertEqual(payload.conversationID, ConversationID("conversation-1"))
        XCTAssertEqual(payload.tokenID, FloorTokenID("token-a"))
        XCTAssertEqual(payload.speakerUserID, UserID("user-a"))
        XCTAssertEqual(payload.speakerDeviceID, DeviceID("device-a"))
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

private extension JSONValue {
    var objectValue: [String: JSONValue]? {
        guard case .object(let value) = self else {
            return nil
        }
        return value
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
