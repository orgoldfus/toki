import XCTest
@testable import TokiCore

final class PeerConnectionManagerTests: XCTestCase {
    func testRoomSnapshotDecodesServerPayloadKeys() throws {
        let data = Data(
            """
            {
              "conversationId": "conversation-1",
              "peers": [
                {
                  "connectionId": "connection-a",
                  "userId": "user-a",
                  "deviceId": "device-a",
                  "active": true
                }
              ]
            }
            """.utf8
        )

        let snapshot = try JSONDecoder().decode(RoomSnapshot.self, from: data)

        XCTAssertEqual(snapshot.conversationID, ConversationID("conversation-1"))
        XCTAssertEqual(snapshot.peers.first?.connectionID, "connection-a")
        XCTAssertEqual(snapshot.peers.first?.userID, UserID("user-a"))
        XCTAssertEqual(snapshot.peers.first?.deviceID, DeviceID("device-a"))
    }

    func testJoinRoomCreatesPeersAndSmallerLocalDeviceSendsOffers() async throws {
        let transport = PeerRecordingRealtimeTransport()
        let factory = RecordingPeerConnectionFactory()
        let manager = PeerConnectionManager(
            localDeviceID: DeviceID("device-b"),
            iceConfig: .stunOnly(urls: ["stun:stun.l.google.com:19302"]),
            transport: transport,
            peerConnectionFactory: factory,
            eventID: IncrementingRealtimeEventID(prefix: "peer"),
            clock: FixedRealtimeClock(now: Date(timeIntervalSince1970: 1_720_000_000))
        )

        try await manager.joinRoom(
            RoomSnapshot(
                conversationID: ConversationID("conversation-1"),
                peers: [
                    RoomPeer(connectionID: "connection-local", userID: UserID("user-local"), deviceID: DeviceID("device-b"), active: true),
                    RoomPeer(connectionID: "connection-a", userID: UserID("user-a"), deviceID: DeviceID("device-a"), active: true),
                    RoomPeer(connectionID: "connection-c", userID: UserID("user-c"), deviceID: DeviceID("device-c"), active: true)
                ]
            )
        )

        XCTAssertEqual(factory.createdPeerDeviceIDs, [DeviceID("device-a"), DeviceID("device-c")])
        XCTAssertEqual(manager.peerStates[DeviceID("device-a")], .connecting)
        XCTAssertEqual(manager.peerStates[DeviceID("device-c")], .connecting)
        XCTAssertEqual(transport.sent.map(\.type), [.signalOffer])
        XCTAssertEqual(transport.sent.first?.conversationID, ConversationID("conversation-1"))
        XCTAssertEqual(transport.sent.first?.payload.objectValue?["targetDeviceId"], .string("device-c"))
        XCTAssertEqual(transport.sent.first?.payload.objectValue?["sdp"], .string("offer-for-device-c"))
    }

    func testSignalsAnswersAndIceCandidatesThroughRealtimeTransport() async throws {
        let transport = PeerRecordingRealtimeTransport()
        let manager = PeerConnectionManager(
            localDeviceID: DeviceID("device-b"),
            iceConfig: .stunOnly(urls: ["stun:stun.l.google.com:19302"]),
            transport: transport,
            peerConnectionFactory: RecordingPeerConnectionFactory(),
            eventID: IncrementingRealtimeEventID(prefix: "signal"),
            clock: FixedRealtimeClock(now: Date(timeIntervalSince1970: 1_720_000_000))
        )
        try await manager.joinRoom(
            RoomSnapshot(
                conversationID: ConversationID("conversation-1"),
                peers: [RoomPeer(connectionID: "connection-a", userID: UserID("user-a"), deviceID: DeviceID("device-a"), active: true)]
            )
        )
        transport.sent.removeAll()

        try await manager.sendAnswer("answer-sdp", to: DeviceID("device-a"))
        try await manager.sendICECandidate("candidate:1 1 udp 1 192.0.2.1 5000 typ host", to: DeviceID("device-a"))

        XCTAssertEqual(transport.sent.map(\.type), [.signalAnswer, .signalIceCandidate])
        XCTAssertEqual(transport.sent.map { $0.payload.objectValue?["targetDeviceId"] }, [.string("device-a"), .string("device-a")])
        XCTAssertEqual(transport.sent.map { $0.payload.objectValue?["sdp"] }, [.string("answer-sdp"), nil])
        XCTAssertEqual(transport.sent.map { $0.payload.objectValue?["candidate"] }, [nil, .string("candidate:1 1 udp 1 192.0.2.1 5000 typ host")])
    }

    func testLeaveRoomClosesConnectionsAndClearsPublishingState() async throws {
        let factory = RecordingPeerConnectionFactory()
        let manager = PeerConnectionManager(
            localDeviceID: DeviceID("device-b"),
            iceConfig: .stunOnly(urls: ["stun:stun.l.google.com:19302"]),
            transport: PeerRecordingRealtimeTransport(),
            peerConnectionFactory: factory,
            eventID: IncrementingRealtimeEventID(prefix: "peer"),
            clock: FixedRealtimeClock(now: Date(timeIntervalSince1970: 1_720_000_000))
        )
        try await manager.joinRoom(
            RoomSnapshot(
                conversationID: ConversationID("conversation-1"),
                peers: [RoomPeer(connectionID: "connection-c", userID: UserID("user-c"), deviceID: DeviceID("device-c"), active: true)]
            )
        )

        try await manager.setPublishingEnabled(true)
        await manager.leaveRoom()

        XCTAssertEqual(factory.connections.first?.closedCount, 1)
        XCTAssertEqual(factory.connections.first?.publishingHistory, [true, false])
        XCTAssertTrue(manager.peerStates.isEmpty)
        XCTAssertFalse(manager.isPublishing)
    }
}

private final class RecordingPeerConnectionFactory: PeerConnectionCreating, @unchecked Sendable {
    private(set) var connections: [RecordingPeerConnection] = []

    var createdPeerDeviceIDs: [DeviceID] {
        connections.map(\.peer.deviceID)
    }

    func makePeerConnection(peer: RoomPeer, iceConfig: ICEConfigResponse) throws -> PeerConnectionControlling {
        let connection = RecordingPeerConnection(peer: peer)
        connections.append(connection)
        return connection
    }
}

private final class RecordingPeerConnection: PeerConnectionControlling, @unchecked Sendable {
    let peer: RoomPeer
    private(set) var closedCount = 0
    private(set) var publishingHistory: [Bool] = []

    init(peer: RoomPeer) {
        self.peer = peer
    }

    func makeOffer() async throws -> String {
        "offer-for-\(peer.deviceID.rawValue)"
    }

    func setPublishingEnabled(_ enabled: Bool) async throws {
        publishingHistory.append(enabled)
    }

    func close() async {
        closedCount += 1
    }
}

private final class PeerRecordingRealtimeTransport: RealtimeTransporting, @unchecked Sendable {
    private(set) var connectedTokens: [String] = []
    var sent: [AnyRealtimeEventEnvelope] = []

    func connect(sessionToken: String) async throws {
        connectedTokens.append(sessionToken)
    }

    func send(_ envelope: AnyRealtimeEventEnvelope) async throws {
        sent.append(envelope)
    }

    func close() async {}
}

private extension JSONValue {
    var objectValue: [String: JSONValue]? {
        guard case .object(let value) = self else {
            return nil
        }
        return value
    }
}
